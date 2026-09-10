import Testing
@testable import PeraperaCore

// The scratch pad's whole value is getting readings for text the learner brought
// themselves. Wrong readings are worse than none: a learner who cannot yet read
// the kanji has no way to catch the error.

@Test func annotatesKanjiAndLeavesKanaAlone() {
    let annotated = JapaneseReadings.annotate("私は学生です")
    #expect(annotated.contains("["))
    // Kana-only runs must survive untouched, brackets and all.
    let segments = Furigana.parse(annotated)
    #expect(segments.map(\.base).joined() == "私は学生です")
}

@Test func textWithNoKanjiIsReturnedUnchanged() {
    #expect(JapaneseReadings.annotate("ひらがなだけ") == "ひらがなだけ")
    #expect(JapaneseReadings.annotate("Hello, world.") == "Hello, world.")
    #expect(JapaneseReadings.annotate("") == "")
}

@Test func whitespaceAndLineBreaksAreThePastedTextsOwn() {
    let source = "山\n川\n\n海"
    let segments = Furigana.parse(JapaneseReadings.annotate(source))
    #expect(segments.map(\.base).joined() == source)
}

@Test func kanjiIsDetectedAcrossTheRangesThatMatter() {
    #expect(JapaneseReadings.containsKanji("学"))
    #expect(JapaneseReadings.containsKanji("あ学あ"))
    #expect(!JapaneseReadings.containsKanji("ひらがな"))
    #expect(!JapaneseReadings.containsKanji("カタカナ"))
    #expect(!JapaneseReadings.containsKanji("123 abc"))
}

@Test func romajiBecomesHiragana() {
    #expect(JapaneseReadings.hiragana(fromLatin: "gakusei") == "がくせい")
    #expect(JapaneseReadings.hiragana(fromLatin: "kippu") == "きっぷ")
}

@Test func theAnnotationRoundTripsThroughTheParserTheAppAlreadyUses() {
    // Whatever this produces has to be renderable by the same code that renders
    // a generated lesson, or the scratch pad needs a second rendering path.
    let annotated = JapaneseReadings.annotate("切符を2枚ください")
    let segments = Furigana.parse(annotated)
    #expect(segments.map(\.base).joined() == "切符を2枚ください")
    #expect(segments.contains { $0.reading != nil })
}

// Okurigana. `Furigana.parse` attaches a reading to the kanji run immediately
// before it, so a base ending in kana is not a reading — it renders as literal
// brackets in the middle of the sentence, which is what shipped.

@Test func okuriganaStaysOutsideTheReading() {
    #expect(JapaneseReadings.annotated(token: "目指し", reading: "めざし") == "目指[めざ]し")
    #expect(JapaneseReadings.annotated(token: "輝く", reading: "かがやく") == "輝[かがや]く")
    #expect(JapaneseReadings.annotated(token: "入ろう", reading: "はいろう") == "入[はい]ろう")
    // 食べる is た + べる, so stripping the shared kana greedily finds the real
    // stem boundary: the reading over 食 is た, not たべ.
    #expect(JapaneseReadings.annotated(token: "食べる", reading: "たべる") == "食[た]べる")
}

@Test func leadingKanaStaysOutsideToo() {
    #expect(JapaneseReadings.annotated(token: "お誕生日", reading: "おたんじょうび")
            == "お誕生日[たんじょうび]")
}

@Test func pureKanjiIsUnchangedByTheSplit() {
    #expect(JapaneseReadings.annotated(token: "教室", reading: "きょうしつ") == "教室[きょうしつ]")
}

@Test func aReadingThatDoesNotAgreeAtTheEdgesIsDropped() {
    // Rather than emitting a base the parser will reject and render as brackets.
    #expect(JapaneseReadings.annotated(token: "目指し", reading: "めざす") == "目指し")
    #expect(JapaneseReadings.annotated(token: "ひらがな", reading: "ひらがな") == "ひらがな")
}

@Test func everyAnnotationSurvivesTheParserForRealSentences() {
    // The round trip that was passing only because every token in it was pure
    // kanji. A leaked bracket shows up here as a base containing "[".
    for source in ["みんなーチルノのさんすう教室はじまるよー",
                   "あたいみたいな天才目指して、がんばっていってね",
                   "キラキラダイアモンド輝く星のように",
                   "栄光志望校なんとかして入ろう",
                   "切符を2枚ください"] {
        let annotated = JapaneseReadings.annotate(source)
        let segments = Furigana.parse(annotated)
        #expect(segments.map(\.base).joined() == source,
                "round trip changed the text for \(source): \(annotated)")
        #expect(!segments.contains { $0.base.contains("[") || $0.base.contains("]") },
                "brackets leaked into the rendered text for \(source): \(annotated)")
    }
}
