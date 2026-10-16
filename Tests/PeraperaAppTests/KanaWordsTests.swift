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

private let dictionary = JapaneseDictionary.bundled()

@Test func theBundledDictionaryAnswersForCommonWords() {
    for word in ["教室", "天才", "新幹線", "南口", "切符", "ラーメン", "きょうしつ"] {
        let entry = dictionary.look(up: word)
        #expect(entry != nil, "\(word) is not in the bundled dictionary")
        #expect(!(entry?.gloss.isEmpty ?? true), "\(word) has no gloss")
    }
}

@Test func furiganaMarkupIsStrippedBeforeLookup() {
    // Words arrive from a lesson carrying their readings.
    #expect(dictionary.look(up: "教室[きょうしつ]")?.gloss
            == dictionary.look(up: "教室")?.gloss)
}

@Test func anUnknownWordFallsThroughRatherThanInventing() {
    #expect(dictionary.look(up: "ぬるぽぬるぽ") == nil)
}

@Test func anEmptyDictionaryAnswersNothingRatherThanCrashing() {
    // What every view holds until the file has been read.
    #expect(JapaneseDictionary.empty.look(up: "教室") == nil)
    #expect(JapaneseDictionary.empty.knownWords.isEmpty)
}

// Segmentation against the real word list. The unit tests use a handful of
// words; these check the file a learner actually gets.

@Test func theWordListSegmentsKanaCompoundsTheTokenizerSplits() {
    let known = dictionary.knownWords
    func words(_ text: String) -> [String] {
        JapaneseText.tokens(in: text, knownWords: known).map(\.text)
    }
    #expect(words("まどぐちは三番です").contains("まどぐち"))
    #expect(words("ゆうびんきょくへ行きます").contains("ゆうびんきょく"))
    // And the particles still stand apart, which is what the tinting needs.
    #expect(words("まどぐちは三番です").contains("は"))
    #expect(words("ゆうびんきょくへ行きます").contains("へ"))
}

@Test func theWordListDoesNotSwallowAParticleItHappensToList() {
    let known = dictionary.knownWords
    // では and ではない are both entries. Merging either hides two particles.
    let tokens = JapaneseText.tokens(in: "学生ではない", knownWords: known).map(\.text)
    #expect(tokens.contains("で"))
    #expect(tokens.contains("は"))
}
