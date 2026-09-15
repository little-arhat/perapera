import Foundation
import Testing
@testable import PeraperaApp
@testable import PeraperaCore

// The bundled word list. A wrong resource path or a schema drift would leave the
// screen empty with no error, so the load is asserted rather than assumed.

private func loadWords() throws -> [ReadingDrill.Word] {
    let url = try #require(Bundle.module.url(forResource: "kana-words",
                                             withExtension: "json", subdirectory: "Words"))
    return try JSONDecoder().decode([ReadingDrill.Word].self, from: Data(contentsOf: url))
}

@Test func theBundledListLoadsAndIsSubstantial() throws {
    let words = try loadWords()
    #expect(words.count > 10_000)
}

@Test func everyWordIsOneScriptAndAUsableLength() throws {
    for word in try loadWords() {
        #expect(["h", "k"].contains(word.script), "\(word.text) has script \(word.script)")
        #expect((2...6).contains(word.text.count), "\(word.text) is the wrong length")
        #expect(!word.gloss.isEmpty, "\(word.text) has no gloss")
        #expect((1...3).contains(word.tier))
    }
}

@Test func theFrequentWordsCarryTheirKanji() throws {
    // A dictionary picture of a hiragana-read word says the kanji, so the words
    // most likely to be drawn had better have it. Loanwords legitimately lack
    // one, which is why the check is on kanji-eligible words, not all.
    let words = try loadWords()
    let frequent = ReadingDrill.mostFrequent(words, script: .hiragana)
    let withKanji = frequent.filter { $0.kanji != nil }
    #expect(withKanji.count * 10 > frequent.count * 9,
            "\(withKanji.count) of \(frequent.count) frequent hiragana words have kanji")
    for word in withKanji {
        #expect(KanaInput.containsKanji(word.kanji!), "\(word.text) -> \(word.kanji!) is not kanji")
    }
    #expect(PictureRequest.dictionaryPool(words, scripts: .katakana).count >= 500)
}

@Test func everyWordRomanisesToSomethingLatin() throws {
    // A word the romaniser cannot read would be unanswerable: the learner types
    // a reading and is told they are wrong whatever they type.
    for word in try loadWords() {
        let romaji = KanaRomaji.romaji(word.text)
        #expect(!romaji.isEmpty, "\(word.text) romanises to nothing")
        #expect(romaji.allSatisfy { $0.isASCII }, "\(word.text) -> \(romaji) kept kana")
        #expect(KanaRomaji.accepts(romaji, for: word.text),
                "\(word.text) does not accept its own romanisation")
    }
}

@Test func bothScriptsHaveEnoughForTheLongestSession() throws {
    let words = try loadWords()
    for script in [ReadingDrill.Script.hiragana, .katakana, .both] {
        let session = ReadingDrill.session(from: words, script: script, size: .large,
                                           progress: [:], today: ReadingDrill.day())
        #expect(session.count == ReadingDrill.Size.large.count,
                "\(script.label) cannot fill a large session")
    }
}

// The offline dictionary. A lookup that waits on a model call is a lookup you
// stop using, so the words a learner actually clicks have to answer instantly.

@Test @MainActor func theBundledDictionaryAnswersForCommonWords() {
    for word in ["教室", "天才", "新幹線", "南口", "切符", "ラーメン", "きょうしつ"] {
        let entry = Bundled.shared.look(up: word)
        #expect(entry != nil, "\(word) is not in the bundled dictionary")
        #expect(!(entry?.gloss.isEmpty ?? true), "\(word) has no gloss")
    }
}

@Test @MainActor func furiganaMarkupIsStrippedBeforeLookup() {
    // Words arrive from a lesson carrying their readings.
    #expect(Bundled.shared.look(up: "教室[きょうしつ]")?.gloss
            == Bundled.shared.look(up: "教室")?.gloss)
}

@Test @MainActor func anUnknownWordFallsThroughRatherThanInventing() {
    #expect(Bundled.shared.look(up: "ぬるぽぬるぽ") == nil)
}
