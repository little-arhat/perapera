import Testing
import Foundation
@testable import FluentCore

/// A real lesson generated with the set-aware prompt.
///
/// The point of sets is repetition on one point, so what this checks is that a
/// lesson actually arrives shaped that way — not merely that it parses.
@Test func realLessonUsesSetsForRepetition() throws {
    let url = try #require(Bundle.module.url(
        forResource: "real-set-lesson", withExtension: "json",
        subdirectory: "Fixtures"))
    struct Generated: Decodable {
        let exercises: [Exercise]
    }
    let lesson = try JSONDecoder().decode(
        Generated.self, from: try Data(contentsOf: url))

    let sets = lesson.exercises.filter {
        if case .set = $0.content { return true }
        return false
    }
    #expect(!sets.isEmpty, "no drills — the lesson is all singletons")

    // Items, not exercises, are what the learner answers.
    let items = lesson.exercises.reduce(0) { $0 + $1.itemCount }
    #expect(items > lesson.exercises.count,
            "sets should make the lesson longer than its exercise count")

    // Every gap says what to type. This is the ambiguity that reads as a bug.
    for exercise in lesson.exercises {
        let needsInstruction: Bool
        switch exercise.content {
        case .cloze, .set: needsInstruction = true
        default: needsInstruction = false
        }
        if needsInstruction {
            let instruction = exercise.instruction ?? ""
            #expect(!instruction.isEmpty, "\(exercise.id) has no instruction")
        }
    }

    // Hints are what make a textbook drill answerable without giving it away.
    if case let .set(items) = sets.first?.content {
        #expect(items.count >= 3)
        #expect(items.allSatisfy { !$0.acceptedAnswers.isEmpty })
    }
}
