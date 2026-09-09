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
                "topics_covered", "breakthroughs", "focus_next_session",
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
        review_results: report.review_results, topics_covered: report.topics_covered,
        breakthroughs: report.breakthroughs, focus_next_session: report.focus_next_session,
        session_notes: report.session_notes, milestones: ["First lesson in the app"])

    let json = try encoded(report)
    // The script accepts strings or objects; strings are the simpler half of
    // that contract and the one the app uses.
    #expect(json["milestones"] as? [String] == ["First lesson in the app"])
}
