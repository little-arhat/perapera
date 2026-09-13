import Testing
@testable import PeraperaCore

// Marking a correct reading wrong is the worst thing this drill can do: the
// learner read the word right and is told they did not.

@Test func plainKanaRomanises() {
    #expect(KanaRomaji.romaji("あさ") == "asa")
    #expect(KanaRomaji.romaji("ねこ") == "neko")
    #expect(KanaRomaji.romaji("さくら") == "sakura")
}

@Test func hepburnIrregularsAreHepburn() {
    #expect(KanaRomaji.romaji("すし") == "sushi")
    #expect(KanaRomaji.romaji("つなみ") == "tsunami")
    #expect(KanaRomaji.romaji("ふじ") == "fuji")
    #expect(KanaRomaji.romaji("ちち") == "chichi")
}

@Test func youonCombineIntoOneSyllable() {
    #expect(KanaRomaji.romaji("きょう") == "kyou")
    #expect(KanaRomaji.romaji("しゃしん") == "shashin")
    #expect(KanaRomaji.romaji("りょこう") == "ryokou")
    #expect(KanaRomaji.romaji("じゅう") == "juu")
}

@Test func sokuonDoublesTheFollowingConsonant() {
    #expect(KanaRomaji.romaji("きっぷ") == "kippu")
    #expect(KanaRomaji.romaji("がっこう") == "gakkou")
    #expect(KanaRomaji.romaji("いっしょ") == "issho")
}

@Test func katakanaUsesTheSameTable() {
    #expect(KanaRomaji.romaji("コーヒー") == "koohii")
    #expect(KanaRomaji.romaji("テレビ") == "terebi")
    #expect(KanaRomaji.romaji("ジャケット") == "jaketto")
}

@Test func theLongVowelMarkRepeatsTheVowelBeforeIt() {
    #expect(KanaRomaji.romaji("ラーメン") == "raamen")
    #expect(KanaRomaji.romaji("スーパー") == "suupaa")
}

// Acceptance.

@Test func kunreiSpellingsAreAccepted() {
    // Both are taught. Neither is a reading error.
    #expect(KanaRomaji.accepts("sushi", for: "すし"))
    #expect(KanaRomaji.accepts("susi", for: "すし"))
    #expect(KanaRomaji.accepts("tsunami", for: "つなみ"))
    #expect(KanaRomaji.accepts("tunami", for: "つなみ"))
    #expect(KanaRomaji.accepts("syashin", for: "しゃしん"))
    #expect(KanaRomaji.accepts("jyuu", for: "じゅう"))
}

@Test func macronsAndDoubledVowelsAgree() {
    #expect(KanaRomaji.accepts("kōhī", for: "コーヒー"))
    #expect(KanaRomaji.accepts("koohii", for: "コーヒー"))
}

@Test func longOAndLongEAreWrittenSeveralWaysAndAllCount() {
    #expect(KanaRomaji.accepts("kyou", for: "きょう"))
    #expect(KanaRomaji.accepts("kyoo", for: "きょう"))
    #expect(KanaRomaji.accepts("kyō", for: "きょう"))
    #expect(KanaRomaji.accepts("sensei", for: "せんせい"))
    #expect(KanaRomaji.accepts("sensee", for: "せんせい"))
}

@Test func nIsAcceptedDoubledAndAsMBeforeALabial() {
    #expect(KanaRomaji.accepts("shinbun", for: "しんぶん"))
    #expect(KanaRomaji.accepts("shimbun", for: "しんぶん"))
    #expect(KanaRomaji.accepts("onnna", for: "おんな") == false)  // not a spelling of it
    #expect(KanaRomaji.accepts("onna", for: "おんな"))
}

@Test func vowelLengthIsStillADistinction() {
    // おばさん is an aunt, おばあさん is a grandmother. Folding these together
    // would tell a learner they read a different word correctly.
    #expect(!KanaRomaji.accepts("obasan", for: "おばあさん"))
    #expect(!KanaRomaji.accepts("obaasan", for: "おばさん"))
}

@Test func aWrongReadingIsRejected() {
    #expect(!KanaRomaji.accepts("inu", for: "ねこ"))
    #expect(!KanaRomaji.accepts("", for: "ねこ"))
    #expect(!KanaRomaji.accepts("   ", for: "ねこ"))
}

@Test func caseAndStraySpacingDoNotMatter() {
    #expect(KanaRomaji.accepts("  SaKuRa ", for: "さくら"))
}
