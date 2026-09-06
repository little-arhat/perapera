import Testing
import Foundation
@testable import FluentCore

// Generation-time strictness: a lesson that fails here is regenerated, so being
// picky is free. The one thing it must never do is pass an exercise the learner
// cannot answer.

func lesson(_ exercises: [[String: Any]]) throws -> Lesson {
    let data = try JSONSerialization.data(withJSONObject: exercises)
    let decoded = try JSONDecoder().decode([Exercise].self, from: data)
    return Lesson(id: "l", title: "t", focus: "f", estimatedMinutes: 5,
                  preamble: nil, exercises: decoded,
                  spec: LessonSpec(mode: .lesson, size: .small, focus: ""),
                  generatedAt: Date())
}

private func base(_ extra: [String: Any]) -> [String: Any] {
    var d: [String: Any] = ["id": "ex-01", "skill": "grammar", "prompt": "Fill it in."]
    d.merge(extra) { _, new in new }
    return d
}

@Test func acceptsAHealthyLesson() throws {
    let l = try lesson([base(["kind": "multipleChoice",
                              "options": ["は", "を", "で"], "correctIndex": 2])])
    #expect(l.validate().isEmpty)
}

@Test func flagsAnEmptyLesson() {
    let l = Lesson(id: "l", title: "t", focus: "f", estimatedMinutes: 5,
                   preamble: nil, exercises: [],
                   spec: LessonSpec(mode: .lesson, size: .small, focus: ""),
                   generatedAt: Date())
    #expect(l.validate() == [.noExercises])
}

@Test func flagsAListeningExerciseWithNothingToHear() throws {
    let l = try lesson([base(["kind": "digitEntry", "skill": "listening",
                              "acceptedAnswers": ["2600"]])])
    #expect(l.validate() == [.silentListening(exerciseID: "ex-01")])
}

@Test func acceptsListeningWhenAudioIsPresent() throws {
    let l = try lesson([base(["kind": "digitEntry", "skill": "listening",
                              "acceptedAnswers": ["2600"],
                              "audioText": "にせんろっぴゃくえん"])])
    #expect(l.validate().isEmpty)
}

@Test func flagsAnAnswerLeakedIntoItsOwnPrompt() throws {
    let leaked = try lesson([base([
        "kind": "cloze",
        "instruction": "Write the whole sentence.",
        "prompt": "Say it: 切符を二枚ください。Now write 切符を二枚ください.",
        "acceptedAnswers": ["切符を二枚ください"],
    ])])
    #expect(leaked.validate() == [.leakedAnswer(exerciseID: "ex-01")])
}

@Test func flagsAChoiceWhosePromptContainsTheCorrectOption() throws {
    let leaked = try lesson([base([
        "kind": "multipleChoice",
        "prompt": "Which is right: 明日新幹線で京都に行きます。?",
        "options": ["明日新幹線で京都に行きます。", "僕は明日京都に新幹線で行きます。"],
        "correctIndex": 0,
    ])])
    #expect(leaked.validate() == [.leakedAnswer(exerciseID: "ex-01")])
}

@Test func flagsAGapWithNoInstruction() throws {
    // 「コンビニ＿水を買います。」 alone cannot tell the learner whether to type
    // just で or the whole sentence, and that ambiguity reads as a broken app.
    let bare = try lesson([base(["kind": "cloze",
                                 "prompt": "「コンビニ＿水を買[か]います。」",
                                 "acceptedAnswers": ["で"]])])
    #expect(bare.validate() == [.missingInstruction(exerciseID: "ex-01")])

    let clear = try lesson([base(["kind": "cloze",
                                  "instruction": "Type only the particle.",
                                  "prompt": "「コンビニ＿水を買[か]います。」",
                                  "acceptedAnswers": ["で"]])])
    #expect(clear.validate().isEmpty)
}

// MARK: - Breadth and depth
//
// Two dimensions kept apart: how many points a lesson touches, and how many
// times it repeats each. Braiding them would make one unreachable.

@Test func depthSetsRepetitionsIndependentlyOfSize() {
    #expect(LessonSpec.Depth.light.itemsPerSet < LessonSpec.Depth.standard.itemsPerSet)
    #expect(LessonSpec.Depth.standard.itemsPerSet < LessonSpec.Depth.drill.itemsPerSet)

    // Same breadth, different depth -- and vice versa.
    let broadShallow = LessonSpec(mode: .lesson, size: .large, depth: .light, focus: "")
    let narrowDeep = LessonSpec(mode: .lesson, size: .small, depth: .drill, focus: "")
    #expect(broadShallow.size != narrowDeep.size)
    #expect(broadShallow.depth != narrowDeep.depth)
}

@Test func lessonsWrittenBeforeDepthExistedStillDecode() throws {
    // The archive must read back everything it wrote; a new field must not make
    // old lessons unopenable.
    let legacy = Data(#"{"mode":"review","size":"small","focus":"counters"}"#.utf8)
    let spec = try JSONDecoder().decode(LessonSpec.self, from: legacy)
    #expect(spec.depth == .standard)
    #expect(spec.size == .small)
    #expect(spec.mode == .review)
}

@Test func aGradedLessonStillAwaitsSubmission() throws {
    // Killed between grading and the database write: the feedback is kept, and
    // the lesson must still offer to finish -- without redoing the exercises.
    let url = try #require(Bundle.module.url(
        forResource: "real-lesson-record", withExtension: "json",
        subdirectory: "Fixtures"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var record = try decoder.decode(LessonRecord.self, from: Data(contentsOf: url))

    record.state = .completed
    #expect(record.awaitsSubmission)
    record.state = .graded
    #expect(record.awaitsSubmission)
    record.state = .submitted
    #expect(!record.awaitsSubmission)
}

@Test func flagsAListeningPromptThatPrintsWhatIsSpoken() throws {
    // Observed in a real lesson: the prompt read
    // 「京都までの新幹線の切符は、はっせんえんです。」いくらですか
    // with the same line as audioText. The answer was on screen, so the audio
    // was decorative and the listening skill went unpractised.
    let leaked = try lesson([base([
        "kind": "digitEntry",
        "skill": "listening",
        "instruction": "Write the number in digits.",
        "prompt": "駅のアナウンス:「切符ははっせんえんです。」いくらですか。",
        "audioText": "切符ははっせんえんです。",
        "acceptedAnswers": ["8000"],
    ])])
    #expect(leaked.validate() == [.transcriptInPrompt(exerciseID: "ex-01")])

    let sound = try lesson([base([
        "kind": "digitEntry",
        "skill": "listening",
        "instruction": "Write the number in digits.",
        "prompt": "駅のアナウンスを聞いてください。いくらですか。",
        "audioText": "切符ははっせんえんです。",
        "acceptedAnswers": ["8000"],
    ])])
    #expect(sound.validate().isEmpty)
}

// MARK: - Lesson sizing
//
// The prompt and the on-screen preview must agree about what was asked for.
// They previously could not: the calculation was private to LessonService, so
// the UI described the request in words while the numbers stayed invisible —
// which is how a lesson generated as `light` reads as a request for `drill`
// being ignored.

@Test func depthSetsItemsPerSetAndSizeSetsBreadth() {
    let smallDrill = LessonPlan.plan(size: .small, depth: .drill, level: "A1",
                                     totalSessions: 3, mode: .lesson, dueCount: 0)
    #expect(smallDrill.exercises == 3)
    #expect(smallDrill.itemsPerSet == 9)
    #expect(smallDrill.items == 27)

    let largeLight = LessonPlan.plan(size: .large, depth: .light, level: "A1",
                                     totalSessions: 3, mode: .lesson, dueCount: 0)
    #expect(largeLight.exercises == 8)
    #expect(largeLight.itemsPerSet == 3)
    #expect(largeLight.items == 24)
}

@Test func breadthAndDepthMoveIndependently() {
    // The whole point of two controls. If either axis moved the other, one of
    // them would be unreachable.
    let base = LessonPlan.plan(size: .medium, depth: .standard, level: "A1",
                               totalSessions: 0, mode: .lesson, dueCount: 0)
    let deeper = LessonPlan.plan(size: .medium, depth: .drill, level: "A1",
                                 totalSessions: 0, mode: .lesson, dueCount: 0)
    let broader = LessonPlan.plan(size: .large, depth: .standard, level: "A1",
                                  totalSessions: 0, mode: .lesson, dueCount: 0)

    #expect(deeper.exercises == base.exercises)
    #expect(deeper.itemsPerSet > base.itemsPerSet)
    #expect(broader.itemsPerSet == base.itemsPerSet)
    #expect(broader.exercises > base.exercises)
}

@Test func reviewCoversWhatIsDue() {
    // A review that leaves due items untouched lets the schedule slip.
    let plan = LessonPlan.plan(size: .small, depth: .light, level: "A1",
                               totalSessions: 0, mode: .review, dueCount: 30)
    #expect(plan.items >= 24, "only \(plan.items) questions for 30 due items")
}

@Test func aDepthLabelCarriesItsNumber() {
    #expect(LessonSpec.Depth.light.detailedLabel.contains("3"))
    #expect(LessonSpec.Depth.drill.detailedLabel.contains("9"))
}

// MARK: - Recognition exercises
//
// The stimulus is a photograph, so the thing that must not slip is the link
// between what the picture will show and what the learner is asked to read.

private func recognition(_ extra: [String: Any] = [:]) -> [String: Any] {
    var d: [String: Any] = [
        "id": "ex-01", "skill": "reading", "kind": "recognition",
        "prompt": "Read the sign.",
        "image": [
            "scene": "A weathered enamel station sign, angled, daylight.",
            "targets": ["でぐち"],
            "question": "What does it say?",
        ],
        "acceptedAnswers": ["でぐち"],
    ]
    d.merge(extra) { _, new in new }
    return d
}

@Test func acceptsAWellFormedRecognitionExercise() throws {
    #expect(try lesson([recognition()]).validate().isEmpty)
}

@Test func flagsAnAnswerThatIsNotInThePicture() throws {
    // Asking the learner to read something the image was never told to draw is
    // unanswerable, and the failure is silent without this check.
    let mismatched = try lesson([recognition([
        "image": [
            "scene": "A sign.",
            "targets": ["でぐち"],
            "question": "What does it say?",
        ],
        "acceptedAnswers": ["いりぐち"],
    ])])
    #expect(mismatched.validate() == [.leakedAnswer(exerciseID: "ex-01")])
}

@Test func rejectsARecognitionExerciseWithNothingToRead() {
    #expect(throws: (any Error).self) {
        try decodeExercise([
            "kind": "recognition",
            "image": ["scene": "A sign.", "targets": [], "question": nil],
            "acceptedAnswers": ["でぐち"],
        ])
    }
}

@Test func recognitionIsGradedLocallyLikeAnyTypedAnswer() throws {
    let ex = try decodeExercise(recognition())
    #expect(Grader.outcome(ex, .text("でぐち")).verdict?.isCorrect == true)
    #expect(Grader.outcome(ex, .text("いりぐち")).verdict?.isCorrect == false)
}

@Test func theImageTextIsNotOfferedAsSelectableText() throws {
    // Otherwise the answer sits on screen beside the question.
    let ex = try decodeExercise(recognition())
    #expect(!ex.displayedText.contains("でぐち"))
    #expect(ex.displayedText.contains("What does it say?"))
}

@Test func droppingAnExerciseRemovesItsAnswersAndImage() throws {
    let url = try #require(Bundle.module.url(
        forResource: "real-lesson-record", withExtension: "json",
        subdirectory: "Fixtures"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var record = try decoder.decode(LessonRecord.self, from: Data(contentsOf: url))

    let victim = record.lesson.exercises[0].id
    record.images[victim] = "\(victim).jpg"
    let before = record.lesson.exercises.count

    let trimmed = record.droppingExercises([victim])
    #expect(trimmed.lesson.exercises.count == before - 1)
    #expect(trimmed.images[victim] == nil)
    #expect(trimmed.answers[victim] == nil)
}

// MARK: - Spending
//
// The app spends the learner's money on their behalf, in amounts too small to
// notice one at a time. The log exists so that is checkable rather than
// discovered on a bill.

@Test func spendingTotalsAcrossCalls() {
    var log = SpendLog()
    log.record(Spend(purpose: "Lesson", model: "opus", costUSD: 0.58))
    log.record(Spend(purpose: "Picture", model: "flash-image", costUSD: 0.069))
    #expect(abs(log.total - 0.649) < 0.0001)
    #expect(log.latest?.purpose == "Picture", "newest first")
}

@Test func trimmingKeepsTheTotalHonest() {
    // Dropping old entries must not quietly reduce what the learner has been
    // told they spent.
    var log = SpendLog()
    for index in 0..<(SpendLog.keepEntries + 50) {
        log.record(Spend(purpose: "call \(index)", model: "m", costUSD: 0.01))
    }
    #expect(log.entries.count == SpendLog.keepEntries)
    #expect(abs(log.total - Double(SpendLog.keepEntries + 50) * 0.01) < 0.0001)
}

@Test func tinyCostsAreNotRoundedToNothing() {
    // Two decimal places would show most calls as $0.00, which reads as free.
    #expect(SpendLog.format(0.00059) == "$0.0006")
    #expect(SpendLog.format(0.069) == "$0.069")
    #expect(SpendLog.format(1.5) == "$1.50")
    #expect(SpendLog.format(0) == "$0")
}

@Test func todayCountsOnlyToday() {
    var log = SpendLog()
    log.record(Spend(purpose: "old", model: "m", costUSD: 5,
                     at: Date().addingTimeInterval(-60 * 60 * 48)))
    log.record(Spend(purpose: "new", model: "m", costUSD: 0.07))
    #expect(abs(log.today - 0.07) < 0.0001)
    #expect(abs(log.total - 5.07) < 0.0001)
}
