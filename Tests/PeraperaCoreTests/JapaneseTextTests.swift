import Testing
@testable import PeraperaCore

// Segmentation is what a learner hovers, what gets tinted, and what a reading is
// attached to. A wrong boundary teaches a word that does not exist.

/// Segmentation with no dictionary: what the kanji rule alone can do.
private func words(_ text: String) -> [String] {
    JapaneseText.tokens(in: text, knownWords: []).map(\.text)
}

/// Segmentation with one. A handful of words, so the test says what it relies
/// on rather than depending on whatever the bundled file happens to list.
private func words(_ text: String, knowing known: Set<String>) -> [String] {
    JapaneseText.tokens(in: text, knownWords: known).map(\.text)
}

@Test func adjacentKanjiCompoundsAreRejoined() {
    // NLTokenizer splits every one of these; a learner memorising 幹線 from
    // 新幹線 has learned a word they will not meet again.
    #expect(words("新幹線に乗ります").starts(with: ["新幹線"]))
    #expect(words("東京駅で会いましょう").starts(with: ["東京駅"]))
    #expect(words("日本語を勉強します").starts(with: ["日本語"]))
}

@Test func particlesStaySeparateFromWhatTheyMark() {
    // The whole point of hovering: を is not part of 切符.
    let tokens = words("切符を2枚ください")
    #expect(tokens.contains("切符"))
    #expect(tokens.contains("を"))
    #expect(!tokens.contains("切符を"))
}

@Test func mergingNeverCrossesAKanaBoundary() {
    // は is kana, so a kana-run merge would swallow it. It must not.
    let tokens = words("南口は広い")
    #expect(tokens.contains("南口"))
    #expect(tokens.contains("は"))
}

@Test func particlesAreRecognisedAsSuch() {
    #expect(JapaneseText.role(of: "は") == .particle)
    #expect(JapaneseText.role(of: "を") == .particle)
    #expect(JapaneseText.role(of: "から") == .particle)
    #expect(JapaneseText.role(of: "新幹線") == .content)
    #expect(JapaneseText.role(of: "ください") == .content)
    #expect(JapaneseText.role(of: "2") == .other)
    #expect(JapaneseText.role(of: "、") == .other)
}

@Test func segmentationCoversEveryCharacterItClaims() {
    // A token whose range does not match its text would tint or hover the wrong
    // span, which is silent and confusing.
    let source = "東京駅から新幹線に乗って京都まで行きます"
    for token in JapaneseText.tokens(in: source, knownWords: []) {
        #expect(String(source[token.range]) == token.text)
    }
}

@Test func mergingIsCappedSoItCannotRunAway() {
    // Seven kanji with no particle is not prose; refusing to merge is safer than
    // inventing one enormous word.
    let tokens = words("東京都特別区港区赤坂")
    #expect(tokens.allSatisfy { $0.count <= 6 })
}

@Test func hoveringFindsTheMergedToken() {
    let source = "新幹線に乗る"
    // Offset 1 is inside 幹, which NLTokenizer would report as part of 幹線.
    #expect(JapaneseText.token(at: 1, in: source, knownWords: [])?.text == "新幹線")
}

@Test func emptyAndLatinTextAreHandled() {
    #expect(words("").isEmpty)
    #expect(!words("hello world").isEmpty)
}

@Test func kanaOnlyTextIsStillSegmentedIntoTappableWords() {
    // All-kana Japanese has no readings to annotate, and is exactly what a
    // beginner pastes into the scratch pad. If it were treated as plain text
    // the words would be inert, which is the whole feature missing.
    let source = "ひらがなだけのぶんです"
    let tokens = JapaneseText.tokens(in: source, knownWords: [])
    #expect(tokens.count > 1, "kana text must still break into words")
    #expect(JapaneseText.token(at: 0, in: source, knownWords: []) != nil)
    for token in tokens {
        #expect(String(source[token.range]) == token.text)
    }
}

@Test func aWordCanBeFoundAtEveryOffsetOfJapaneseText() {
    // A click lands on a UTF-16 offset; every one inside the string has to
    // resolve to something, or some characters are silently unclickable.
    let source = "切符を2枚ください"
    for offset in 0..<source.utf16.count {
        #expect(JapaneseText.token(at: offset, in: source, knownWords: []) != nil,
                "offset \(offset) resolves to no word")
    }
}

// A dictionary is the only thing that can tell まど + ぐち is one word: both
// halves are words too, so no rule about character classes reaches it.

@Test func aKnownWordIsRejoinedEvenWhenBothHalvesAreAlsoWords() {
    #expect(words("まどぐちは三番です").contains("まどぐち") == false,
            "no dictionary, no join -- that is the point of the next one")
    #expect(words("まどぐちは三番です", knowing: ["まどぐち", "まど", "ぐち"])
            .contains("まどぐち"))
}

@Test func theLongestKnownSpanWinsNotTheFirst() {
    // The tokenizer gives ゆうびん + きょく. Both the first pair and the whole
    // are listed, so taking the first match would stop at ゆうびん.
    let known: Set<String> = ["ゆうびん", "きょく", "ゆうびんきょく"]
    let tokens = words("ゆうびんきょくへ行きます", knowing: known)
    #expect(tokens.contains("ゆうびんきょく"))
    #expect(!tokens.contains("ゆうびん"))
    #expect(tokens.contains("へ"))
}

@Test func aParticleIsNeverSwallowedEvenWhenTheDictionaryListsTheSpan() {
    // では and ではない are both real entries. Joining either hides the two
    // particles this app exists to make visible.
    let tokens = words("学生ではない", knowing: ["では", "ではない", "学生"])
    #expect(tokens.contains("で"))
    #expect(tokens.contains("は"))
    #expect(!tokens.contains("では"))
}

@Test func aKnownJoinIsCappedLikeTheKanjiOne() {
    // A listed form long enough to span a clause is more likely a phrase the
    // tokenizer should have broken up than a word worth highlighting, so the
    // span is never even tested past the cap.
    let long = "あいうえおかきくけこ"
    let tokens = words(long, knowing: [long])
    #expect(!tokens.contains(long))
    #expect(tokens.allSatisfy { $0.count <= 8 })
}

@Test func joiningLeavesEveryCharacterAccountedFor() {
    let source = "まどぐちは三番です"
    let known: Set<String> = ["まどぐち", "まど", "ぐち", "三番", "です"]
    for token in JapaneseText.tokens(in: source, knownWords: known) {
        #expect(String(source[token.range]) == token.text)
    }
    for offset in 0..<source.utf16.count {
        #expect(JapaneseText.token(at: offset, in: source, knownWords: known) != nil,
                "offset \(offset) resolves to no word")
    }
}
