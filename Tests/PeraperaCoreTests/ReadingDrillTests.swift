import Foundation
import Testing
@testable import PeraperaCore

private func word(_ text: String, _ script: String = "h", tier: Int = 1) -> ReadingDrill.Word {
    ReadingDrill.Word(w: text, g: "gloss", s: script, t: tier)
}

private let pool = (1...200).map { word("ひ\($0)", "h", tier: $0 % 5 == 0 ? 2 : 1) }
    + (1...60).map { word("カ\($0)", "k", tier: 1) }

// Selection

@Test func aSessionIsTheSizeAsked() {
    for size in ReadingDrill.Size.allCases {
        let session = ReadingDrill.session(from: pool, script: .both, size: size,
                                           progress: [:], today: 100, shuffle: { $0 })
        #expect(session.count == size.count)
    }
}

@Test func theScriptFilterIsRespected() {
    let hira = ReadingDrill.session(from: pool, script: .hiragana, size: .small,
                                    progress: [:], today: 100, shuffle: { $0 })
    #expect(hira.allSatisfy { $0.script == "h" })
    let kata = ReadingDrill.session(from: pool, script: .katakana, size: .small,
                                    progress: [:], today: 100, shuffle: { $0 })
    #expect(kata.allSatisfy { $0.script == "k" })
}

@Test func dueWordsComeBeforeNewOnes() {
    // The point of a schedule: a word you nearly forgot outranks one you have
    // never met.
    var progress: [String: ReadingDrill.Progress] = [:]
    for index in 1...5 {
        var p = ReadingDrill.Progress()
        p.seen = 3
        p.due = 90
        progress["ひ\(index)"] = p
    }
    let session = ReadingDrill.session(from: pool, script: .hiragana, size: .small,
                                       progress: progress, today: 100, shuffle: { $0 })
    #expect(Set(session.prefix(5).map(\.text)) == Set((1...5).map { "ひ\($0)" }))
}

@Test func aWordNotYetDueIsNotShown() {
    var progress: [String: ReadingDrill.Progress] = [:]
    var p = ReadingDrill.Progress()
    p.seen = 3
    p.due = 200          // not due until day 200
    progress["ひ1"] = p
    let session = ReadingDrill.session(from: pool, script: .hiragana, size: .small,
                                       progress: progress, today: 100, shuffle: { $0 })
    #expect(!session.contains { $0.text == "ひ1" })
}

@Test func mostWordsComeFromTheCommonTiers() {
    let session = ReadingDrill.session(from: pool, script: .hiragana, size: .large,
                                       progress: [:], today: 100, shuffle: { $0 })
    let rare = session.filter { $0.tier > 1 }.count
    #expect(rare > 0, "a session of only the most common words never widens")
    #expect(Double(rare) / Double(session.count) < 0.35, "too many rare words")
}

@Test func anEmptyPoolIsAnEmptySession() {
    #expect(ReadingDrill.session(from: [], script: .both, size: .small,
                                 progress: [:], today: 1).isEmpty)
}

// Scheduling

@Test func aRightAnswerPushesTheWordFurtherOut() {
    var p = ReadingDrill.Progress()
    p = ReadingDrill.record(p, wasCorrect: true, today: 10)
    #expect(p.interval == 1)
    #expect(p.due == 11)
    p = ReadingDrill.record(p, wasCorrect: true, today: 11)
    #expect(p.interval == 6)
    p = ReadingDrill.record(p, wasCorrect: true, today: 17)
    #expect(p.interval > 6)
}

@Test func aWrongAnswerBringsItBackTomorrowNotImmediately() {
    // Re-showing it in the same session tests the last few seconds, not the word.
    var p = ReadingDrill.Progress()
    p.interval = 30
    p.due = 100
    let after = ReadingDrill.record(p, wasCorrect: false, today: 100)
    #expect(after.interval == 1)
    #expect(after.due == 101)
}

@Test func easeMovesWithPerformanceAndStaysInRange() {
    var p = ReadingDrill.Progress()
    for _ in 0..<20 { p = ReadingDrill.record(p, wasCorrect: false, today: 1) }
    #expect(p.ease >= 1.3)
    for _ in 0..<40 { p = ReadingDrill.record(p, wasCorrect: true, today: 1) }
    #expect(p.ease <= 2.8)
}

@Test func countsAreKept() {
    var p = ReadingDrill.Progress()
    p = ReadingDrill.record(p, wasCorrect: true, today: 1)
    p = ReadingDrill.record(p, wasCorrect: false, today: 1)
    #expect(p.seen == 2)
    #expect(p.correct == 1)
}
