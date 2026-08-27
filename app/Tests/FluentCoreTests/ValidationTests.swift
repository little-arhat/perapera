import Testing
import Foundation
@testable import FluentCore

// Generation-time strictness: a lesson that fails here is regenerated, so being
// picky is free. The one thing it must never do is pass an exercise the learner
// cannot answer.

private func lesson(_ exercises: [[String: Any]]) throws -> Lesson {
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
