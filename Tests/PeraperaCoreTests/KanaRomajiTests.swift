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
    #expect(KanaRomaji.accepts("onna", for: "おんな"))
    // onnna is what an IME takes for おんな, so it is a spelling of it.
    #expect(KanaRomaji.accepts("onnna", for: "おんな"))
    // m only before a labial: しんぶん is shimbun, あんない is not amnai.
    #expect(!KanaRomaji.accepts("amnai", for: "あんない"))
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

// Spellings the earlier normalise-and-compare approach got wrong, kept as the
// reason the matcher was rewritten.

@Test func geminatedChiIsTchiAsWellAsCchi() {
    // tchi is the standard Hepburn and was being rejected.
    #expect(KanaRomaji.accepts("kotchi", for: "こっち"))
    #expect(KanaRomaji.accepts("kocchi", for: "こっち"))
    #expect(KanaRomaji.romaji("こっち") == "kotchi")
}

@Test func theHyphenIsALongVowel() {
    #expect(KanaRomaji.accepts("ko-hi-", for: "コーヒー"))
    #expect(KanaRomaji.accepts("ra-men", for: "ラーメン"))
}

@Test func mIsOnlyAcceptedBeforeALabial() {
    #expect(KanaRomaji.accepts("shimbun", for: "しんぶん"))
    #expect(KanaRomaji.accepts("sampo", for: "さんぽ"))
    #expect(!KanaRomaji.accepts("amnai", for: "あんない"))
    #expect(!KanaRomaji.accepts("hom", for: "ほん"))
}

@Test func hiraganaLongVowelsTakeEveryWrittenForm() {
    for typed in ["toukyou", "tookyoo", "tōkyō"] {
        #expect(KanaRomaji.accepts(typed, for: "とうきょう"), "\(typed) rejected")
    }
}

@Test func aVowelThatIsNotLengtheningStaysItsOwnSyllable() {
    // あう is au, not "aa". こい is koi, not "koo".
    #expect(KanaRomaji.accepts("au", for: "あう"))
    #expect(!KanaRomaji.accepts("aa", for: "あう"))
    #expect(KanaRomaji.accepts("koi", for: "こい"))
    #expect(!KanaRomaji.accepts("koo", for: "こい"))
}

@Test func wapuroSpellingsFromAnImeAreAccepted() {
    #expect(KanaRomaji.accepts("jyugyou", for: "じゅぎょう"))
    #expect(KanaRomaji.accepts("jugyou", for: "じゅぎょう"))
    #expect(KanaRomaji.accepts("syashin", for: "しゃしん"))
    #expect(KanaRomaji.accepts("cyotto", for: "ちょっと"))
}
