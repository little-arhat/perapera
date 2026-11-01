import Foundation
import Testing
@testable import PeraperaCore

// The scratch pad held one text and overwrote it. What the learner brings
// themselves is the one thing a lesson cannot supply, so the history has to
// behave like a list of their materials rather than a log of keystrokes.

private let day = Date(timeIntervalSince1970: 1_700_000_000)

@Test func readingATextPutsItAtTheTop() {
    var history = ScratchHistory()
    history.record("まどぐちは三番です", at: day)
    history.record("切符を二枚ください", at: day.addingTimeInterval(60))
    #expect(history.entries.map(\.text)
            == ["切符を二枚ください", "まどぐちは三番です"])
}

@Test func rereadingATextMovesItRatherThanDuplicatingIt() {
    var history = ScratchHistory()
    history.record("メニュー", at: day)
    history.record("看板", at: day.addingTimeInterval(60))
    let first = history.entries.last?.id
    history.record("メニュー", at: day.addingTimeInterval(120))

    #expect(history.entries.count == 2)
    #expect(history.entries.first?.text == "メニュー")
    // The same entry, not a new one: the learner has one menu.
    #expect(history.entries.first?.id == first)
    #expect(history.entries.first?.readAt == day.addingTimeInterval(120))
}

@Test func surroundingWhitespaceDoesNotMakeANewEntry() {
    var history = ScratchHistory()
    history.record("メニュー", at: day)
    history.record("  メニュー\n", at: day.addingTimeInterval(60))
    #expect(history.entries.count == 1)
}

@Test func anEmptyTextIsNotRecorded() {
    var history = ScratchHistory()
    history.record("   \n\n ", at: day)
    history.record("", at: day)
    #expect(history.entries.isEmpty)
}

@Test func theOldestFallOffTheEnd() {
    var history = ScratchHistory()
    for index in 0...ScratchHistory.limit {
        history.record("text \(index)", at: day.addingTimeInterval(Double(index)))
    }
    #expect(history.entries.count == ScratchHistory.limit)
    #expect(history.entries.first?.text == "text \(ScratchHistory.limit)")
    #expect(!history.entries.contains { $0.text == "text 0" })
}

@Test func anEntryCanBeRemoved() {
    var history = ScratchHistory()
    history.record("メニュー", at: day)
    let id = try! #require(history.entries.first?.id)
    history.remove(id: id)
    #expect(history.entries.isEmpty)
    #expect(history.entry(id: id) == nil)
}

@Test func aRowShowsItsFirstLineAndItsLength() {
    let entry = ScratchEntry(text: "一行目\n二行目\n三行目", readAt: day)
    #expect(entry.summary == "一行目")
    #expect(entry.characterCount == 11)

    let long = ScratchEntry(text: String(repeating: "あ", count: 80), readAt: day)
    #expect(long.summary.count == 61, "truncated, with the ellipsis")
    #expect(long.summary.hasSuffix("…"))
}

@Test func theHistorySurvivesARoundTripThroughDisk() throws {
    var history = ScratchHistory()
    history.record("メニュー", at: day)
    let data = try JSONEncoder().encode(history)
    #expect(try JSONDecoder().decode(ScratchHistory.self, from: data) == history)
}
