import Testing
@testable import FluentCore

// The converter's job is to give kana and stop -- no kanji, no candidates. Its
// correctness is what makes a production exercise test production.

private func kana(_ romaji: String) -> String {
    KanaInput.convert(romaji).display
}

@Test func convertsBasicSyllables() {
    #expect(kana("aiueo") == "あいうえお")
    #expect(kana("konnichiha") == "こんにちは")
    #expect(kana("sakana") == "さかな")
    #expect(kana("tokyo") == "ときょ")       // とうきょう needs the long vowel typed
    #expect(kana("toukyou") == "とうきょう")
}

@Test func handlesSokuon() {
    // The geminates that carry meaning -- the ones missed in session 1.
    #expect(kana("kippu") == "きっぷ")
    #expect(kana("hassen") == "はっせん")
    #expect(kana("happyaku") == "はっぴゃく")
    #expect(kana("roppyaku") == "ろっぴゃく")
    #expect(kana("ippon") == "いっぽん")
    #expect(kana("gakkou") == "がっこう")
}

@Test func handlesN() {
    #expect(kana("san") == "さん")
    #expect(kana("sanzen") == "さんぜん")
    #expect(kana("nihon") == "にほん")
    // "n" before a vowel must NOT swallow it: na is な, not んあ.
    #expect(kana("nani") == "なに")
    #expect(kana("anata") == "あなた")
    // Forced ん before a vowel or y.
    #expect(kana("hon'ya") == "ほんや")
    #expect(kana("shinnya") == "しんにゃ")
    // ん before y without the apostrophe stays にゃ-style, as an IME does.
    #expect(kana("kinyou") == "きにょう")
}

@Test func handlesYouon() {
    #expect(kana("kyou") == "きょう")
    #expect(kana("shashin") == "しゃしん")
    #expect(kana("chotto") == "ちょっと")
    #expect(kana("jugyou") == "じゅぎょう")
    #expect(kana("hyaku") == "ひゃく")
    #expect(kana("ryokou") == "りょこう")
}

@Test func acceptsKunreiAndWapuroSpellings() {
    // A learner who typed si/tu/hu meant し/つ/ふ.
    #expect(kana("si") == kana("shi"))
    #expect(kana("tu") == kana("tsu"))
    #expect(kana("hu") == kana("fu"))
    #expect(kana("zi") == kana("ji"))
}

@Test func holdsIncompleteSyllablesAsPending() {
    // Typing "ki" one letter at a time: "k" is not yet kana, "ki" is.
    let partial = KanaInput.convert("k")
    #expect(partial.kana == "")
    #expect(partial.pending == "k")

    let complete = KanaInput.convert("ki")
    #expect(complete.kana == "き")
    #expect(complete.pending == "")

    // Mid-word: committed kana stays put while the tail waits.
    let midword = KanaInput.convert("kippuwoky")
    #expect(midword.kana == "きっぷを")
    #expect(midword.pending == "ky")
}

@Test func passesThroughPunctuationAndDigits() {
    #expect(kana("2mai") == "2まい")
    #expect(kana("kippu, onegai") == "きっぷ, おねがい")
}

@Test func convertsKatakana() {
    #expect(KanaInput.convert("hoteru", script: .katakana).display == "ホテル")
    #expect(KanaInput.convert("ko-hi-", script: .katakana).display == "コーヒー")
    #expect(KanaInput.convert("konbini", script: .katakana).display == "コンビニ")
    #expect(KanaInput.convert("kippu", script: .katakana).display == "キップ")
}

@Test func neverProducesKanji() {
    // The whole point: no candidate list, so nothing here can become kanji.
    for romaji in ["kippu", "toukyou", "densha", "nihon", "kyouto"] {
        let output = kana(romaji)
        let hasKanji = output.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        #expect(!hasKanji, "\(romaji) produced kanji: \(output)")
    }
}

@Test func doubledNResolvesByWhatFollows() {
    // Both letters spell one ん when the second cannot start a syllable...
    #expect(kana("kinn") == "きん")
    // ...but the second n starts に when a vowel follows it.
    #expect(kana("sannen") == "さんねん")
    #expect(kana("onnanoko") == "おんなのこ")
}

@Test func trailingNStaysPendingWhileTyping() {
    // Mid-typing, "n" must not commit: the next letter decides between な and ん.
    let typing = KanaInput.convert("na", finalizing: false)
    #expect(typing.display == "な")

    let holding = KanaInput.convert("n", finalizing: false)
    #expect(holding.kana == "")
    #expect(holding.pending == "n")

    // On commit there is nothing more coming, so it becomes ん.
    #expect(KanaInput.convert("n", finalizing: true).display == "ん")
    #expect(KanaInput.convert("hon", finalizing: true).display == "ほん")
    #expect(KanaInput.convert("hon", finalizing: false).display == "ほn")
}

@Test func conversionIsIdempotentOverAlreadyConvertedKana() {
    // The field holds kana and is re-converted on every keystroke, so kana must
    // pass through untouched or the text would degrade as you type.
    for text in ["きっぷ", "さんぜんはっぴゃくえん", "きっぷを2枚ください", "コーヒー"] {
        #expect(KanaInput.convert(text).display == text, "mangled: \(text)")
    }
    // And converting a mixed field advances only the new romaji.
    #expect(KanaInput.convert("きっぷwo").display == "きっぷを")
}
