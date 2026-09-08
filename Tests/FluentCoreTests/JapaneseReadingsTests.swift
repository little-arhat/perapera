import Testing
@testable import FluentCore

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
