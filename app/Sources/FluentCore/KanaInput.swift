import Foundation

/// Romaji → kana, with no candidate list.
///
/// This exists because of a specific failure. The system IME converts kana to
/// kanji from a candidate list, so typing Japanese tests whether the learner
/// *recognizes* the right kanji among options -- not whether they can *recall*
/// the word. A learner can appear to produce 切符 while being unable to say
/// きっぷ a day later. This converter gives kana and stops there, so a
/// production exercise tests production.
///
/// Pure and incremental: it takes whatever has been typed and returns the kana
/// so far plus the romaji still waiting for more letters, so a view can render
/// "き" the moment "ki" is typed while "ky" stays pending.
public enum KanaInput {
    public enum Script: Sendable {
        case hiragana, katakana
    }

    public struct Conversion: Equatable, Sendable {
        /// Fully converted kana.
        public let kana: String
        /// Romaji that could still become kana once more letters arrive.
        public let pending: String

        /// What the learner should see: committed kana with the in-flight
        /// romaji trailing it, the way an IME shows an uncommitted syllable.
        public var display: String { kana + pending }

        public init(kana: String, pending: String) {
            self.kana = kana
            self.pending = pending
        }
    }

    /// - Parameter finalizing: while the learner is still typing, a trailing
    ///   lone `n` must stay pending -- committing it to ん immediately would turn
    ///   "na" into んあ instead of な. On commit there is nothing more coming, so
    ///   the trailing n becomes ん.
    public static func convert(
        _ romaji: String, script: Script = .hiragana, finalizing: Bool = true
    ) -> Conversion {
        var kana = ""
        var rest = Substring(romaji.lowercased())

        while !rest.isEmpty {
            // Punctuation and anything non-alphabetic passes through untouched,
            // so a learner can type 「、」or a digit mid-sentence.
            if let first = rest.first, !first.isLetter, first != "-" {
                kana.append(first)
                rest = rest.dropFirst()
                continue
            }

            // Long-vowel mark, katakana's own convention (コーヒー).
            if rest.first == "-" {
                kana.append(script == .katakana ? "ー" : "-")
                rest = rest.dropFirst()
                continue
            }

            // Sokuon: a doubled consonant becomes っ + the syllable.
            // きっぷ, はっせん, いっぽん -- the geminates that carry meaning.
            if rest.count >= 2 {
                let first = rest[rest.startIndex]
                let second = rest[rest.index(after: rest.startIndex)]
                if first == second, isConsonant(first), first != "n" {
                    kana.append(small(script))
                    rest = rest.dropFirst()
                    continue
                }
            }

            // ん. The subtle case in the whole converter: "n" is both a syllable
            // onset (な, に, にゃ) and a mora of its own (ん), so how many
            // letters it consumes depends on what follows.
            if rest.first == "n" {
                let afterN = rest.dropFirst()
                let syllable = script == .katakana ? "ン" : "ん"

                if afterN.first == "'" {                       // n' forces ん
                    kana.append(syllable)
                    rest = afterN.dropFirst()
                    continue
                }
                if afterN.isEmpty {
                    guard finalizing else {
                        // Still typing: hold it, the next letter decides.
                        return Conversion(kana: kana, pending: String(rest))
                    }
                    kana.append(syllable)
                    rest = afterN
                    continue
                }
                if afterN.first == "n" {
                    // "konnichiha" is ん + に, but "kinn" is just ん. Which one
                    // depends on whether the SECOND n can start a syllable:
                    // if a vowel or y follows it, it does (にちは); if not, both
                    // letters were spelling the single mora ん.
                    let afterSecondN = afterN.dropFirst()
                    let secondNStartsSyllable = afterSecondN.first.map {
                        !isConsonant($0) || $0 == "y"
                    } ?? false
                    kana.append(syllable)
                    rest = secondNStartsSyllable ? afterN : afterSecondN
                    continue
                }
                if isConsonant(afterN.first!), afterN.first! != "y" {
                    kana.append(syllable)                      // ん before a consonant
                    rest = afterN
                    continue
                }
                // Otherwise a vowel or y follows: な / に / にゃ. Fall through
                // to the table.
            }

            // Longest match wins: "kyo" before "ky", "ky" before "k".
            var matched = false
            for length in stride(from: min(3, rest.count), through: 1, by: -1) {
                let candidate = String(rest.prefix(length))
                if let syllable = table[candidate] {
                    kana.append(convert(syllable: syllable, to: script))
                    rest = rest.dropFirst(length)
                    matched = true
                    break
                }
            }
            if matched { continue }

            // No match. If what remains could still become a syllable, hold it
            // as pending rather than emitting garbage; otherwise pass it through
            // so a typo stays visible instead of vanishing.
            if isPrefixOfSyllable(String(rest)) {
                return Conversion(kana: kana, pending: String(rest))
            }
            kana.append(rest.first!)
            rest = rest.dropFirst()
        }

        return Conversion(kana: kana, pending: "")
    }

    /// Converts between the two kana scripts.
    ///
    /// They sit exactly 0x60 apart in Unicode, so this is a shift rather than a
    /// table. Anything that is not kana — kanji, latin, punctuation, the
    /// long-vowel mark — passes through untouched, which is what makes it safe
    /// to run over a whole phrase.
    public static func convertKana(_ text: String, to script: Script) -> String {
        let hiragana = 0x3041...0x3096
        let katakana = 0x30A1...0x30F6
        return String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            switch script {
            case .katakana where hiragana.contains(Int(scalar.value)):
                Unicode.Scalar(scalar.value + 0x60) ?? scalar
            case .hiragana where katakana.contains(Int(scalar.value)):
                Unicode.Scalar(scalar.value - 0x60) ?? scalar
            default:
                scalar
            }
        }))
    }

    /// Whether a string contains any kanji — i.e. whether it can be read at all
    /// without knowing them.
    public static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || scalar.value == 0x3005
        }
    }

    private static func small(_ script: Script) -> String {
        script == .katakana ? "ッ" : "っ"
    }

    private static func isConsonant(_ c: Character) -> Bool {
        c.isLetter && !"aiueo".contains(c)
    }

    /// Katakana sits exactly 0x60 above hiragana in Unicode, so one table serves
    /// both scripts.
    private static func convert(syllable: String, to script: Script) -> String {
        guard script == .katakana else { return syllable }
        return String(String.UnicodeScalarView(syllable.unicodeScalars.map { scalar in
            (0x3041...0x3096).contains(scalar.value)
                ? Unicode.Scalar(scalar.value + 0x60)! : scalar
        }))
    }

    private static func isPrefixOfSyllable(_ text: String) -> Bool {
        text.count <= 3 && table.keys.contains { $0.hasPrefix(text) }
    }

    /// Hepburn, plus the kunrei and wapuro spellings a learner is likely to
    /// type (si/shi, tu/tsu, hu/fu, zi/ji).
    static let table: [String: String] = {
        var t: [String: String] = [
            "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
            "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
            "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご",
            "sa": "さ", "shi": "し", "si": "し", "su": "す", "se": "せ", "so": "そ",
            "za": "ざ", "ji": "じ", "zi": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",
            "ta": "た", "chi": "ち", "ti": "ち", "tsu": "つ", "tu": "つ",
            "te": "て", "to": "と",
            "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど",
            "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
            "ha": "は", "hi": "ひ", "fu": "ふ", "hu": "ふ", "he": "へ", "ho": "ほ",
            "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",
            "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
            "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
            "ya": "や", "yu": "ゆ", "yo": "よ",
            "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",
            "wa": "わ", "wo": "を", "wi": "ゐ", "we": "ゑ",
            // Small kana, for spellings like ファ and ティ.
            "la": "ぁ", "li": "ぃ", "lu": "ぅ", "le": "ぇ", "lo": "ぉ",
            "xa": "ぁ", "xi": "ぃ", "xu": "ぅ", "xe": "ぇ", "xo": "ぉ",
            "lya": "ゃ", "lyu": "ゅ", "lyo": "ょ", "ltu": "っ", "xtu": "っ",
            "va": "ゔぁ", "vi": "ゔぃ", "vu": "ゔ", "ve": "ゔぇ", "vo": "ゔぉ",
            "fa": "ふぁ", "fi": "ふぃ", "fe": "ふぇ", "fo": "ふぉ",
        ]
        // Youon: consonant + ゃゅょ. きゃ, しゅ, ちょ, にゃ, ぴょ...
        let youon: [(String, String)] = [
            ("ky", "き"), ("gy", "ぎ"), ("sh", "し"), ("sy", "し"), ("j", "じ"),
            ("zy", "じ"), ("ch", "ち"), ("ty", "ち"), ("dy", "ぢ"), ("ny", "に"),
            ("hy", "ひ"), ("by", "び"), ("py", "ぴ"), ("my", "み"), ("ry", "り"),
        ]
        for (prefix, base) in youon {
            for (vowel, small) in [("a", "ゃ"), ("u", "ゅ"), ("o", "ょ")] {
                t[prefix + vowel] = base + small
            }
            // "sha"/"cha"/"ja" also spell the -i syllable alone: shi, chi, ji.
            t[prefix + "i"] = t[prefix + "i"] ?? base
        }
        return t
    }()
}
