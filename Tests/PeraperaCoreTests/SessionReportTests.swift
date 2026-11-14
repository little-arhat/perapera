import Testing
import Foundation
@testable import PeraperaCore

// The app and `update-db.py` meet at exactly one value: SessionReport. If its
// encoded shape drifts from what the script parses, lessons stop being recorded
// and nothing else in the app would notice. These tests pin the wire format.

private func encoded(_ report: SessionReport) throws -> [String: Any] {
    let data = try JSONEncoder().encode(report)
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

private func sampleReport() -> SessionReport {
    SessionReport(
        session_id: "session-003",
        date: "2026-08-26",
        duration_minutes: 14,
        command_used: "fluent-app",
        skills_practiced: ["grammar", "vocabulary"],
        skill_scores: [
            "grammar": .init(exercises: 4, correct: 3, time_minutes: 8),
            "vocabulary": .init(exercises: 2, correct: 2, time_minutes: 6),
        ],
        errors: [
            .init(pattern_id: "counter_placement", category: "grammar",
                  subcategory: "counters", your_answer: "はがき三枚をください",
                  correct_answer: "はがきを三枚ください",
                  context: "post office", severity: "moderate",
                  difficulty_score: 0.7, notes: nil)
        ],
        new_vocabulary: [
            .init(item_id: "vocab_hagaki", item_type: "vocabulary", content: "はがき",
                  answer: "postcard", category: "travel", difficulty: "A1",
                  initial_quality: 3, priority: "medium")
        ],
        review_results: [.init(item_id: "vocab_kippu", quality: 4)],
        pattern_results: [.init(pattern_id: "counter_placement", attempts: 9, correct: 6)],
        topics_covered: ["counters"],
        breakthroughs: [],
        focus_next_session: ["を placement"],
        session_notes: "Counters still not automatic.",
        milestones: []
    )
}

@Test func reportUsesTheSnakeCaseKeysTheScriptReads() throws {
    let json = try encoded(sampleReport())
    // Required by update-db.py; a missing one exits 1.
    #expect(json["session_id"] as? String == "session-003")
    #expect(json["date"] as? String == "2026-08-26")
    // Optional but consumed -- these are the keys documented in DB_SCRIPTS.md.
    for key in ["duration_minutes", "command_used", "skills_practiced",
                "skill_scores", "errors", "new_vocabulary", "review_results",
                "pattern_results", "topics_covered", "breakthroughs", "focus_next_session",
                "session_notes", "milestones"] {
        #expect(json[key] != nil, "missing top-level key '\(key)'")
    }
}

@Test func nestedRecordsUseTheirDocumentedKeys() throws {
    let json = try encoded(sampleReport())

    let score = (json["skill_scores"] as! [String: Any])["grammar"] as! [String: Any]
    #expect(score["exercises"] as? Int == 4)
    #expect(score["correct"] as? Int == 3)
    #expect(score["time_minutes"] as? Int == 8)

    let error = (json["errors"] as! [[String: Any]])[0]
    #expect(error["pattern_id"] as? String == "counter_placement")
    #expect(error["your_answer"] as? String == "はがき三枚をください")
    #expect(error["correct_answer"] as? String == "はがきを三枚ください")
    #expect(error["severity"] as? String == "moderate")

    // The payload says item_id/item_type even though the stored record says
    // id/type -- these are two different values, and the boundary renames.
    let vocab = (json["new_vocabulary"] as! [[String: Any]])[0]
    #expect(vocab["item_id"] as? String == "vocab_hagaki")
    #expect(vocab["item_type"] as? String == "vocabulary")

    let review = (json["review_results"] as! [[String: Any]])[0]
    #expect(review["item_id"] as? String == "vocab_kippu")
    #expect(review["quality"] as? Int == 4)

    // Same id as the error above, deliberately: one point, counted from both
    // sides. update-db.py keys mastery-db.patterns on it.
    let pattern = (json["pattern_results"] as! [[String: Any]])[0]
    #expect(pattern["pattern_id"] as? String == "counter_placement")
    #expect(pattern["attempts"] as? Int == 9)
    #expect(pattern["correct"] as? Int == 6)
}

@Test func reviewQualityStaysInSM2Range() throws {
    // update-db.py feeds quality straight into the SM-2 formula; anything
    // outside 0-5 corrupts the easiness factor rather than erroring.
    for score in 0...10 {
        let quality = Verdict(isCorrect: score >= 6, score: score, correctVersion: "").quality
        #expect((0...5).contains(quality), "score \(score) produced quality \(quality)")
    }
}

@Test func milestonesEncodeAsBareStrings() throws {
    var report = sampleReport()
    report = SessionReport(
        session_id: report.session_id, date: report.date,
        duration_minutes: report.duration_minutes, command_used: report.command_used,
        skills_practiced: report.skills_practiced, skill_scores: report.skill_scores,
        errors: report.errors, new_vocabulary: report.new_vocabulary,
        review_results: report.review_results, pattern_results: report.pattern_results,
        topics_covered: report.topics_covered,
        breakthroughs: report.breakthroughs, focus_next_session: report.focus_next_session,
        session_notes: report.session_notes, milestones: ["First lesson in the app"])

    let json = try encoded(report)
    // The script accepts strings or objects; strings are the simpler half of
    // that contract and the one the app uses.
    #expect(json["milestones"] as? [String] == ["First lesson in the app"])
}

// MARK: - The grammar point an exercise drills

@Test func anExerciseCarriesThePointItDrills() throws {
    let ex = try decodeExercise([
        "kind": "cloze", "pattern": "particle_de_location",
        "acceptedAnswers": ["で"],
    ])
    #expect(ex.pattern == "particle_de_location")
}

@Test func anUntaggedExerciseHasNoPoint() throws {
    // Archived lessons predate the field, and a comprehension question about
    // a passage has no single point to name. Both must decode.
    let ex = try decodeExercise(["kind": "cloze", "acceptedAnswers": ["で"]])
    #expect(ex.pattern == nil)
}

@Test func aBlankPointIsNoPoint() throws {
    // A tally keyed on "" or " " would merge unrelated exercises under one
    // meaningless id and poison the mastery it feeds.
    for blank in ["", "   "] {
        let ex = try decodeExercise([
            "kind": "cloze", "pattern": blank, "acceptedAnswers": ["で"],
        ])
        #expect(ex.pattern == nil)
    }
}

@Test func thePointSurvivesTheArchive() throws {
    let ex = try decodeExercise([
        "kind": "cloze", "pattern": "counter_mai", "acceptedAnswers": ["三枚"],
    ])
    let round = try JSONDecoder().decode(
        Exercise.self, from: try JSONEncoder().encode(ex))
    #expect(round.pattern == "counter_mai")
}

// MARK: - Tallying a point

private func drill(_ pattern: String?, items: Int) throws -> Exercise {
    var fields: [String: Any] = ["kind": "set", "items": (1...items).map {
        ["prompt": "q\($0)", "acceptedAnswers": ["a\($0)"]]
    }]
    if let pattern { fields["pattern"] = pattern }
    return try decodeExercise(fields)
}

@Test func aDrillCountsOnceForEveryAnswerInIt() throws {
    // Seven of nine right in one set is seven answers on that point, not one
    // exercise "passed" -- the repetition is the signal.
    let results = SessionReport.patternResults(of: [try drill("counter_mai", items: 9)]) { _ in 8 }
    #expect(results.count == 1)
    #expect(results[0].pattern_id == "counter_mai")
    #expect(results[0].attempts == 9)
    #expect(results[0].correct == 7)
}

@Test func drillsOnTheSamePointAddUp() throws {
    let exercises = [try drill("particle_de", items: 5), try drill("particle_de", items: 3)]
    let results = SessionReport.patternResults(of: exercises) { $0.itemCount == 5 ? 10 : 0 }
    #expect(results.count == 1)
    #expect(results[0].attempts == 8)
    #expect(results[0].correct == 5)
}

@Test func anUnansweredExerciseIsNotCountedEitherWay() throws {
    // Abandoning a lesson halfway must not read as failing its last points.
    let results = SessionReport.patternResults(of: [try drill("te_form", items: 5)]) { _ in nil }
    #expect(results.isEmpty)
}

@Test func anUntaggedExerciseTalliesNothing() throws {
    let results = SessionReport.patternResults(of: [try drill(nil, items: 5)]) { _ in 10 }
    #expect(results.isEmpty)
}

@Test func aTeacherScoreOutsideTheScaleCannotInventAnswers() throws {
    // Grading is the one score the app does not compute; a model that returns
    // 12 out of 10 must not produce more correct answers than there were items.
    let exercise = try drill("kanji_reading", items: 4)
    let high = SessionReport.patternResults(of: [exercise]) { _ in 12 }
    #expect(high[0].correct == 4)
    let low = SessionReport.patternResults(of: [exercise]) { _ in -3 }
    #expect(low[0].correct == 0)
}
