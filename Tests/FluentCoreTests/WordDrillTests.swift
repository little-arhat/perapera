import Testing
import Foundation
@testable import FluentCore

private func word(
    _ content: String, _ gloss: String, kind: SavedItem.Kind = .word,
    reading: String? = nil, example: String? = nil
) -> SavedItem {
    SavedItem(content: content, gloss: gloss, kind: kind, sourceLessonId: nil,
              reading: reading, example: example)
}

@Test func drillsInBothDirections() {
    let items = [word("切符", "ticket", reading: "きっぷ")]

    let recognise = WordDrill.build(from: items, direction: .toNative)
    #expect(recognise.questions.first?.shown == "切符")
    #expect(recognise.questions.first?.accepted == ["ticket"])

    let recall = WordDrill.build(from: items, direction: .toTarget)
    #expect(recall.questions.first?.shown == "ticket")
    // Typing the reading is knowing the word, and kana is the only keyboard
    // the app offers.
    #expect(recall.questions.first?.accepted.contains("切符") == true)
    #expect(recall.questions.first?.accepted.contains("きっぷ") == true)
}

@Test func unanswerableEntriesAreSkippedNotShown() {
    // A word with no gloss cannot be translated into English; asking anyway
    // teaches nothing and looks like a bug.
    let items = [word("切符", ""), word("駅", "station")]
    #expect(WordDrill.build(from: items, direction: .toNative).questions.count == 1)
    #expect(WordDrill.build(from: items, direction: .toTarget).questions.count == 1)
}

@Test func marksAnswersWithTheSameRulesAsALesson() {
    let drill = WordDrill.build(
        from: [word("切符", "ticket", reading: "きっぷ")], direction: .toTarget)
    let question = drill.questions[0]

    #expect(drill.mark(question, answer: "切符")?.isCorrect == true)
    #expect(drill.mark(question, answer: "きっぷ")?.isCorrect == true)
    #expect(drill.mark(question, answer: "はがき")?.isCorrect == false)
}

@Test func aNearMissOnAnEnglishGlossIsNotFailed() {
    // Glosses vary — "ticket" against "a ticket" is not a mistake worth
    // calling one, so the app declines to rule rather than marking it wrong.
    let drill = WordDrill.build(from: [word("切符", "ticket")], direction: .toNative)
    let outcome = drill.mark(drill.questions[0], answer: "a ticket")
    #expect(outcome == nil, "should defer, got \(String(describing: outcome))")
}

@Test func weakestWordsAreDrilledFirst() {
    var saved = SavedItems(items: [
        word("A", "a"), word("B", "b"), word("C", "c"),
    ])
    // A answered wrong, B answered right, C never tried.
    saved.record(id: SavedItem.identifier(for: "A"), wasCorrect: false)
    saved.record(id: SavedItem.identifier(for: "B"), wasCorrect: true)

    // Wrong before untried: demonstrated failure is stronger evidence of need
    // than no evidence. Always-right comes last.
    let order = saved.drillCandidates(limit: 3).map { Furigana.stripped($0.content) }
    #expect(order == ["A", "C", "B"], "got \(order)")
}

@Test func partlyKnownWordsSortByHowBadlyTheyAreKnown() {
    var saved = SavedItems(items: [word("A", "a"), word("B", "b")])
    let a = SavedItem.identifier(for: "A"), b = SavedItem.identifier(for: "B")
    // A at 1/3, B at 2/3.
    saved.record(id: a, wasCorrect: true)
    saved.record(id: a, wasCorrect: false)
    saved.record(id: a, wasCorrect: false)
    saved.record(id: b, wasCorrect: true)
    saved.record(id: b, wasCorrect: true)
    saved.record(id: b, wasCorrect: false)

    let order = saved.drillCandidates(limit: 2).map { Furigana.stripped($0.content) }
    #expect(order == ["A", "B"], "got \(order)")
}

@Test func recordingADrillResultUpdatesAccuracy() {
    var saved = SavedItems(items: [word("切符", "ticket")])
    let id = SavedItem.identifier(for: "切符")
    #expect(saved.items[0].accuracy == nil)

    saved.record(id: id, wasCorrect: true)
    saved.record(id: id, wasCorrect: false)
    #expect(saved.items[0].attempts == 2)
    #expect(saved.items[0].accuracy == 0.5)
}

@Test func enrichmentFillsGapsWithoutOverwritingTheLearner() {
    var saved = SavedItems(items: [word("切符", "my own note")])
    let id = SavedItem.identifier(for: "切符")

    saved.enrich(id: id, gloss: "ticket", reading: "きっぷ",
                 example: "切符を二枚ください。", exampleGloss: "Two tickets, please.")

    // The learner's own gloss is theirs and stays.
    #expect(saved.items[0].gloss == "my own note")
    #expect(saved.items[0].reading == "きっぷ")
    #expect(saved.items[0].example == "切符を二枚ください。")
}

@Test func aDrillIsCappedToTheRequestedLength() {
    let many = (1...20).map { word("語\($0)", "word \($0)") }
    #expect(WordDrill.build(from: many, direction: .toNative, limit: 8).questions.count == 8)
}
