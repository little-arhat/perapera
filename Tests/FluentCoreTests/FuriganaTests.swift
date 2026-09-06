import Testing
@testable import FluentCore

// Furigana is withheld by default: a learner who always sees the reading never
// learns to read the kanji. So the parser's job is to keep base text and
// reading separable, exactly, in both directions.

@Test func parsesAnnotatedKanji() {
    let segments = Furigana.parse("切符[きっぷ]を2枚[まい]ください")
    #expect(segments == [
        .init(base: "切符", reading: "きっぷ"),
        .init(base: "を2", reading: nil),
        .init(base: "枚", reading: "まい"),
        .init(base: "ください", reading: nil),
    ])
}

@Test func readingCoversOnlyTheKanjiRun() {
    // 買[か]います annotates 買, never 買います -- the okurigana is already kana.
    let segments = Furigana.parse("買[か]います")
    #expect(segments == [
        .init(base: "買", reading: "か"),
        .init(base: "います", reading: nil),
    ])
}

@Test func strippedTextIsWhatGetsGraded() {
    #expect(Furigana.stripped("切符[きっぷ]を2枚[まい]ください") == "切符を2枚ください")
    #expect(Furigana.stripped("明日[あした]電車[でんしゃ]で行[い]きます")
            == "明日電車で行きます")
}

@Test func readingTextIsFullKana() {
    // What a voice should say when the kanji is ambiguous.
    #expect(Furigana.reading("切符[きっぷ]を2枚[まい]ください") == "きっぷを2まいください")
}

@Test func plainTextPassesThroughUnchanged() {
    let plain = "コンビニで水を買います"
    #expect(Furigana.parse(plain) == [.init(base: plain, reading: nil)])
    #expect(Furigana.stripped(plain) == plain)
    #expect(!Furigana.hasAnnotations(plain))
    #expect(Furigana.hasAnnotations("水[みず]"))
}

@Test func malformedBracketsStayVisible() {
    // Nothing should silently vanish: a stray bracket is a visible oddity, not
    // a hole in the sentence.
    #expect(Furigana.stripped("これは[") == "これは[")
    #expect(Furigana.stripped("[きっぷ]") == "[きっぷ]")     // no kanji to annotate
    #expect(Furigana.stripped("かな[よみ]") == "かな[よみ]")  // preceding text is kana
    #expect(Furigana.stripped("水[]") == "水[]")            // empty reading
}

@Test func handlesRepetitionMarkAndMultipleAnnotations() {
    #expect(Furigana.stripped("人々[ひとびと]") == "人々")
    let segments = Furigana.parse("東京[とうきょう]から京都[きょうと]まで")
    #expect(segments.filter { $0.reading != nil }.count == 2)
}

@Test func parenthesizedKeepsReadingsWhereRubyCannotBeDrawn() {
    // Markdown contexts — a lesson preamble, a feedback comment — cannot host
    // ruby. Stripping would throw away the one thing a beginner most needs from
    // an unfamiliar kanji, so the reading becomes a parenthetical instead.
    #expect(Furigana.parenthesized("切符[きっぷ]を2枚[まい]ください")
            == "切符（きっぷ）を2枚（まい）ください")
    // Unannotated text is untouched.
    #expect(Furigana.parenthesized("コンビニで水を買います") == "コンビニで水を買います")
    // And nothing is left behind that looks like markup.
    #expect(!Furigana.parenthesized("明日[あした]").contains("["))
}
