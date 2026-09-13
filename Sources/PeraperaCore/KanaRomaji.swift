import Foundation

/// Kana to Hepburn, and whether what the learner typed counts.
///
/// The drill is "read this and type how it sounds", so the judgement about what
/// counts is the whole exercise. Too strict and a correct reading is marked
/// wrong on a spelling convention the learner was never taught; too loose and
/// おばさん and おばあさん become the same answer, which is a real distinction
/// about a real word.
///
/// The line drawn here: every common romanisation of a sound is accepted
/// (shi/si, tsu/tu, ja/zya, macrons, ん as n or nn), and vowel length is not.
public enum KanaRomaji {
    /// Two-kana combinations first — they must win over the single-kana table.
    private static let digraphs: [String: String] = [
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
        "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
        "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
        "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
        "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
        "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
        "ぢゃ": "ja", "ぢゅ": "ju", "ぢょ": "jo",
        "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
        "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
        // Katakana-only combinations, which loanwords need.
        "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo", "ふゅ": "fyu",
        "うぃ": "wi", "うぇ": "we", "うぉ": "wo",
        "ゔぁ": "va", "ゔぃ": "vi", "ゔぇ": "ve", "ゔぉ": "vo",
        "てぃ": "ti", "でぃ": "di", "とぅ": "tu", "どぅ": "du",
        "しぇ": "she", "じぇ": "je", "ちぇ": "che",
        "つぁ": "tsa", "つぃ": "tsi", "つぇ": "tse", "つぉ": "tso",
        "くぁ": "kwa", "ぐぁ": "gwa",
    ]

    private static let singles: [String: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "ゐ": "i", "ゑ": "e", "を": "o", "ん": "n",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ゔ": "vu",
        "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o",
        "ゃ": "ya", "ゅ": "yu", "ょ": "yo", "ゎ": "wa",
    ]

    /// Katakana folded to hiragana, so one table serves both.
    public static func toHiragana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0x30A1...0x30F6).contains(scalar.value)
                ? Unicode.Scalar(scalar.value - 0x60)! : scalar
        }))
    }

    /// Hepburn, with a long vowel written as the doubled vowel.
    public static func romaji(_ kana: String) -> String {
        let text = Array(toHiragana(kana))
        var out = ""
        var index = 0

        while index < text.count {
            let character = text[index]

            // ー repeats the vowel of whatever came before it.
            if character == "ー" || character == "〜" {
                if let last = out.last, "aiueo".contains(last) { out.append(last) }
                index += 1
                continue
            }
            // っ doubles the consonant that follows.
            if character == "っ" {
                let rest = romaji(String(text[(index + 1)...]))
                if let first = rest.first, !"aiueon".contains(first) {
                    out.append(first)
                }
                out += rest
                return out
            }
            if index + 1 < text.count,
               let pair = digraphs[String([character, text[index + 1]])] {
                out += pair
                index += 2
                continue
            }
            out += singles[String(character)] ?? String(character)
            index += 1
        }
        return out
    }

    /// Whether what was typed is a reading of this word.
    public static func accepts(_ typed: String, for kana: String) -> Bool {
        !typed.trimmingCharacters(in: .whitespaces).isEmpty
            && normalise(typed) == normalise(romaji(kana))
    }

    /// Folds the spellings that mean the same sound onto one form.
    ///
    /// Kunrei (si, tu, zya) and Hepburn (shi, tsu, ja) are both taught, macrons
    /// and doubled vowels are both standard, and ん is written n or nn depending
    /// on who taught you. None of those is a reading error. Vowel *length* is
    /// preserved, because おばさん and おばあさん are different words.
    public static func normalise(_ romaji: String) -> String {
        var text = romaji.lowercased()
        // Macrons become the doubled vowel they stand for. This must run before
        // any diacritic folding, which would turn ō into a bare o and lose the
        // length -- kōhī would then read as kohi and a correct answer would be
        // marked wrong.
        for (from, to) in [("ā", "aa"), ("ī", "ii"), ("ū", "uu"),
                           ("ē", "ee"), ("ō", "oo"),
                           ("â", "aa"), ("î", "ii"), ("û", "uu"),
                           ("ê", "ee"), ("ô", "oo")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        text = text.folding(options: .diacriticInsensitive,
                            locale: Locale(identifier: "en_US_POSIX"))
        for (from, to) in [("'", ""), ("-", ""), (" ", ""), ("_", "")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        // Kunrei and other common spellings onto Hepburn. Longest first, so
        // "sya" is not eaten by the "si" rule.
        for (from, to) in [
            ("shi", "si"), ("chi", "ti"), ("tsu", "tu"), ("fu", "hu"),
            ("sha", "sya"), ("shu", "syu"), ("sho", "syo"),
            ("cha", "tya"), ("chu", "tyu"), ("cho", "tyo"),
            ("ja", "zya"), ("ju", "zyu"), ("jo", "zyo"), ("ji", "zi"),
            ("jya", "zya"), ("jyu", "zyu"), ("jyo", "zyo"),
            ("dzu", "zu"), ("nn", "n"), ("mb", "nb"), ("mp", "np"), ("mm", "nm"),
        ] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        // Long o and long e are written several ways and all are correct.
        text = text.replacingOccurrences(of: "ou", with: "oo")
        text = text.replacingOccurrences(of: "ei", with: "ee")
        return text
    }
}
