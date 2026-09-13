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
