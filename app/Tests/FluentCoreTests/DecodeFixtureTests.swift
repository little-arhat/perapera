import Testing
import Foundation
@testable import FluentCore

/// Decodes a lesson the live model actually produced.
///
/// Hand-written fixtures test the decoder against what we *imagined* the model
/// would emit. This one is real output, captured from `claude -p` with the
/// shipping prompt and schema, so it catches the gap between the two.
@Test func decodesARealGeneratedLesson() throws {
    let url = try #require(Bundle.module.url(
        forResource: "real-generated-lesson", withExtension: "json",
        subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)

    struct Generated: Decodable {
        let title: String
        let focus: String
        let estimatedMinutes: Int
        let preamble: String?
        let exercises: [Exercise]
    }

    let lesson = try JSONDecoder().decode(Generated.self, from: data)
    #expect(lesson.exercises.count == 6)

    // Every exercise must be renderable: the decoder rejects any whose
    // kind-specific fields are missing, so reaching here proves all 8 are.
    let kinds = Set(lesson.exercises.map { exercise -> String in
        switch exercise.content {
        case .multipleChoice: "multipleChoice"
        case .cloze: "cloze"
        case .reorder: "reorder"
        case .matching: "matching"
        case .digitEntry: "digitEntry"
        case .flashcard: "flashcard"
        case .translation: "translation"
        case .freeResponse: "freeResponse"
        case .set: "set"
        case .recognition: "recognition"
        }
    })
    #expect(kinds.contains("reorder"))
    #expect(kinds.contains("cloze"))
    #expect(kinds.contains("multipleChoice"))

    // A review lesson exists to cover due items; untagged exercises would
    // silently skip the schedule.
    let untagged = lesson.exercises.filter { $0.reviewItemIds.isEmpty }
    #expect(untagged.isEmpty, "untagged: \(untagged.map(\.id))")

    // Every exercise teaches, not just tests.
    let unexplained = lesson.exercises.filter { ($0.explanation ?? "").isEmpty }
    #expect(unexplained.isEmpty, "no explanation: \(unexplained.map(\.id))")
}

/// A listening exercise with nothing to listen to is unanswerable.
@Test func listeningExercisesCarryAudio() throws {
    let url = try #require(Bundle.module.url(
        forResource: "real-generated-lesson", withExtension: "json",
        subdirectory: "Fixtures"))
    struct Generated: Decodable { let exercises: [Exercise] }
    let lesson = try JSONDecoder().decode(
        Generated.self, from: try Data(contentsOf: url))

    let silent = lesson.exercises.filter {
        $0.skill == .listening && ($0.audioText ?? "").isEmpty
    }
    #expect(silent.isEmpty, "listening exercise with no audioText: \(silent.map(\.id))")
}


/// Comprehension: several questions hanging off one text. The passage must be
/// byte-identical across them, or the learner sees it re-stated slightly
/// differently each time and cannot trust what they read.
@Test func comprehensionQuestionsShareOneVerbatimPassage() throws {
    let url = try #require(Bundle.module.url(
        forResource: "real-generated-lesson", withExtension: "json",
        subdirectory: "Fixtures"))
    struct Generated: Decodable { let exercises: [Exercise] }
    let lesson = try JSONDecoder().decode(
        Generated.self, from: try Data(contentsOf: url))

    let passages = Set(lesson.exercises.compactMap(\.passage))
    #expect(passages.count == 1, "expected one shared passage, got \(passages.count)")
    #expect(lesson.exercises.filter { $0.passage != nil }.count >= 2)
}

/// Furigana must reach the learner, and must strip cleanly back to plain text.
@Test func generatedTextCarriesUsableFurigana() throws {
    let url = try #require(Bundle.module.url(
        forResource: "real-generated-lesson", withExtension: "json",
        subdirectory: "Fixtures"))
    struct Generated: Decodable { let exercises: [Exercise] }
    let lesson = try JSONDecoder().decode(
        Generated.self, from: try Data(contentsOf: url))

    let annotated = lesson.exercises.filter { Furigana.hasAnnotations($0.prompt) }
    #expect(!annotated.isEmpty, "no prompt carried furigana")

    // Stripping must leave no bracket residue anywhere.
    for exercise in lesson.exercises {
        let plain = Furigana.stripped(exercise.prompt)
        #expect(!plain.contains("["), "residue in \(exercise.id): \(plain)")
        #expect(!plain.contains("]"), "residue in \(exercise.id): \(plain)")
    }

    // acceptedAnswers must stay unannotated -- they are compared to typed input.
    for exercise in lesson.exercises {
        if case let .cloze(accepted) = exercise.content {
            for answer in accepted {
                #expect(!answer.contains("["),
                        "\(exercise.id) annotated an accepted answer: \(answer)")
            }
        }
    }
}
