import Foundation

/// Kana to Hepburn, and whether what the learner typed counts.
///
/// Marking a correct reading wrong is the worst thing a reading drill can do, so
/// the judgement is built rather than guessed: every kana contributes the set of
/// spellings it can legitimately have, and the answer is accepted if it can be
/// cut into one spelling per kana, in order, with nothing left over.
///
/// That is exact in a way that normalising both sides and comparing is not. The
/// earlier version folded `shi`→`si` and `ou`→`oo` globally and then checked for
/// equality, which quietly rejected `kotchi` — the standard Hepburn for っち —
/// and `ko-hi-`, and would have accepted `m` for ん anywhere rather than only
/// before a labial.
///
/// The per-token approach is taken from a standalone katakana drill written in
/// another session; the tables and the matcher below are a port of its idea.
public enum KanaRomaji {
    // MARK: - Tables
    //
    // First spelling is the canonical Hepburn one, which is what gets displayed.
    // The rest are accepted: kunrei and wāpuro are both taught, and neither is a
    // reading error.

    static let digraphs: [String: [String]] = {
        var table: [String: [String]] = [
            "てぃ": ["ti", "thi"], "でぃ": ["di", "dhi"],
            "とぅ": ["tu", "twu"], "どぅ": ["du", "dwu"],
            "てゅ": ["tyu", "thu"], "でゅ": ["dyu", "dhu"],
            "ふぁ": ["fa"], "ふぃ": ["fi"], "ふぇ": ["fe"], "ふぉ": ["fo"], "ふゅ": ["fyu"],
            "うぃ": ["wi", "ui"], "うぇ": ["we", "ue"], "うぉ": ["wo", "uo"],
            "ゔぁ": ["va"], "ゔぃ": ["vi"], "ゔぇ": ["ve"], "ゔぉ": ["vo"],
            "つぁ": ["tsa"], "つぃ": ["tsi"], "つぇ": ["tse"], "つぉ": ["tso"],
            "いぇ": ["ye"], "くぁ": ["kwa"], "ぐぁ": ["gwa"],
            "しぇ": ["she", "sye"], "じぇ": ["je", "jye", "zye"],
            "ちぇ": ["che", "tye", "cye"],
        ]
        // Yōon, built rather than listed: every one is a consonant cluster plus
        // a small vowel, and writing out sixty rows invites a typo in one.
        let stems: [String: [String]] = [
            "き": ["ky"], "ぎ": ["gy"], "に": ["ny"], "ひ": ["hy"], "び": ["by"],
            "ぴ": ["py"], "み": ["my"], "り": ["ry"],
            "し": ["sh", "sy"], "じ": ["j", "jy", "zy"], "ぢ": ["j", "jy", "dy"],
            "ち": ["ch", "ty", "cy"],
        ]
        for (kana, prefixes) in stems {
            for (small, vowel) in ["ゃ": "a", "ゅ": "u", "ょ": "o"] {
                table[kana + small] = prefixes.map { $0 + vowel }
            }
        }
        return table
    }()

    static let singles: [String: [String]] = [
        "あ": ["a"], "い": ["i"], "う": ["u"], "え": ["e"], "お": ["o"],
        "か": ["ka"], "き": ["ki"], "く": ["ku"], "け": ["ke"], "こ": ["ko"],
        "さ": ["sa"], "し": ["shi", "si", "ci"], "す": ["su"], "せ": ["se"], "そ": ["so"],
        "た": ["ta"], "ち": ["chi", "ti"], "つ": ["tsu", "tu"], "て": ["te"], "と": ["to"],
        "な": ["na"], "に": ["ni"], "ぬ": ["nu"], "ね": ["ne"], "の": ["no"],
        "は": ["ha"], "ひ": ["hi"], "ふ": ["fu", "hu"], "へ": ["he"], "ほ": ["ho"],
        "ま": ["ma"], "み": ["mi"], "む": ["mu"], "め": ["me"], "も": ["mo"],
        "や": ["ya"], "ゆ": ["yu"], "よ": ["yo"],
        "ら": ["ra"], "り": ["ri"], "る": ["ru"], "れ": ["re"], "ろ": ["ro"],
        "わ": ["wa"], "ゐ": ["i", "wi"], "ゑ": ["e", "we"], "を": ["o", "wo"],
        "が": ["ga"], "ぎ": ["gi"], "ぐ": ["gu"], "げ": ["ge"], "ご": ["go"],
        "ざ": ["za"], "じ": ["ji", "zi"], "ず": ["zu"], "ぜ": ["ze"], "ぞ": ["zo"],
        "だ": ["da"], "ぢ": ["ji", "di", "zi"], "づ": ["zu", "du", "dzu"],
        "で": ["de"], "ど": ["do"],
        "ば": ["ba"], "び": ["bi"], "ぶ": ["bu"], "べ": ["be"], "ぼ": ["bo"],
        "ぱ": ["pa"], "ぴ": ["pi"], "ぷ": ["pu"], "ぺ": ["pe"], "ぽ": ["po"],
        "ゔ": ["vu", "bu"],
        "ぁ": ["a"], "ぃ": ["i"], "ぅ": ["u"], "ぇ": ["e"], "ぉ": ["o"],
        "ゃ": ["ya"], "ゅ": ["yu"], "ょ": ["yo"], "ゎ": ["wa"],
    ]

    private static let macron: [Character: String] = ["a": "ā", "i": "ī", "u": "ū",
                                                      "e": "ē", "o": "ō"]

    /// What a kana lengthener is written as when spelled out. ー has no letter.
    private static func literalLengthener(_ character: Character) -> String? {
        switch character {
        case "う": "u"
        case "い": "i"
        default: nil
        }
    }
    private static let circumflex: [Character: String] = ["a": "â", "i": "î", "u": "û",
                                                          "e": "ê", "o": "ô"]

    // MARK: - Tokenising

    struct Token {
        var spellings: [String]
        /// ん, whose spelling depends on what follows it.
        var isSyllabicN = false
        /// Preceded by っ, which doubles the consonant that starts this token.
        var geminated = false
        /// The kana that lengthen this token's vowel: ー, or the う/い that do
        /// the same job in hiragana. Kept rather than counted, because the
        /// spellings differ -- とう is tou as well as too and tō, while ラー is
        /// raa and ra- but never "rau".
        var lengtheners: [Character] = []
    }

    /// Katakana folded to hiragana, so one table serves both.
    public static func toHiragana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0x30A1...0x30F6).contains(scalar.value)
                ? Unicode.Scalar(scalar.value - 0x60)! : scalar
        }))
    }

    static func tokenize(_ kana: String) -> [Token] {
        let characters = Array(toHiragana(kana))
        var tokens: [Token] = []
        var geminate = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "っ" {
                geminate = true
                index += 1
                continue
            }
            if character == "ー" || character == "〜" {
                if !tokens.isEmpty { tokens[tokens.count - 1].lengtheners.append("ー") }
                index += 1
                continue
            }
            // In hiragana the long vowel is written with a kana: おう and えい.
            // Only after the matching vowel -- あう is au, こい is koi.
            if let last = tokens.last, let vowel = last.spellings.first?.last,
               !last.isSyllabicN,
               (character == "う" && (vowel == "o" || vowel == "u"))
                   || (character == "い" && vowel == "e") {
                tokens[tokens.count - 1].lengtheners.append(character)
                index += 1
                continue
            }
            if index + 1 < characters.count,
               let pair = digraphs[String([character, characters[index + 1]])] {
                tokens.append(Token(spellings: pair, geminated: geminate))
                geminate = false
                index += 2
                continue
            }
            if character == "ん" {
                tokens.append(Token(spellings: ["n"], isSyllabicN: true, geminated: geminate))
            } else {
                tokens.append(Token(spellings: singles[String(character)]
                                    ?? [String(character)], geminated: geminate))
            }
            geminate = false
            index += 1
        }
        return tokens
    }

    /// Every spelling this token may take, in this position.
    static func spellings(at index: Int, in tokens: [Token]) -> [String] {
        let token = tokens[index]
        var options: [String]

        if token.isSyllabicN {
            options = ["n", "nn", "n'"]
            // m only before a labial. しんぶん is shimbun; あんない is not amnai.
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            if let next, !next.isSyllabicN,
               next.spellings.contains(where: { "bmp".contains($0.first ?? " ") }) {
                options.append("m")
            }
        } else {
            options = token.spellings
        }

        if token.geminated {
            options = options.flatMap { spelling -> [String] in
                // っち is tchi in Hepburn and cchi in wāpuro. Both are written.
                if spelling.hasPrefix("ch") { return ["t" + spelling, "c" + spelling] }
                if let first = spelling.first, "aiueo".contains(first) { return [spelling] }
                return [String(spelling.first!) + spelling]
            }
        }

        if !token.lengtheners.isEmpty {
            let count = token.lengtheners.count
            let literal = token.lengtheners.compactMap(literalLengthener).joined()
            options = options.flatMap { spelling -> [String] in
                guard let vowel = spelling.last, let mac = macron[vowel] else { return [spelling] }
                let stem = String(spelling.dropLast())
                var forms = [spelling + String(repeating: String(vowel), count: count),
                             spelling + String(repeating: "-", count: count)]
                if count == 1 {
                    forms.append(stem + mac)
                    forms.append(stem + (circumflex[vowel] ?? mac))
                }
                // とう is also spelled tou, せんせい also sensei -- and those are
                // the forms most people write.
                if !literal.isEmpty { forms.append(spelling + literal) }
                return forms
            }
        }
        return options
    }

    // MARK: - Reading and judging

    /// Hepburn, with a long vowel written as the doubled vowel. For display.
    public static func romaji(_ kana: String) -> String {
        let tokens = tokenize(kana)
        return tokens.indices.map { index -> String in
            let token = tokens[index]
            var spelling = token.isSyllabicN
                ? (spellings(at: index, in: tokens).contains("m") ? "m" : "n")
                : (token.spellings.first ?? "")
            if token.geminated, let first = spelling.first, !"aiueo".contains(first) {
                spelling = (spelling.hasPrefix("ch") ? "t" : String(first)) + spelling
            }
            if !token.lengtheners.isEmpty, let vowel = spelling.last, macron[vowel] != nil {
                // Spelled out where the kana spells it out: kyou, sensei. Doubled
                // where the mark does: koohii, raamen.
                let literal = token.lengtheners.compactMap(literalLengthener).joined()
                spelling += literal.isEmpty
                    ? String(repeating: String(vowel), count: token.lengtheners.count)
                    : literal
            }
            return spelling
        }.joined()
    }

    /// Whether what was typed is a reading of this word.
    ///
    /// Matched by walking the tokens and tracking every position the input could
    /// have reached. Exact: it accepts the combinations of per-kana spellings and
    /// nothing else, so no fold can quietly let a wrong reading through.
    public static func accepts(_ typed: String, for kana: String) -> Bool {
        let input = Array(typed.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: ""))
        guard !input.isEmpty else { return false }

        let tokens = tokenize(kana)
        guard !tokens.isEmpty else { return false }

        var reachable: Set<Int> = [0]
        for index in tokens.indices {
            var next: Set<Int> = []
            for option in spellings(at: index, in: tokens) {
                let characters = Array(option)
                for position in reachable where position + characters.count <= input.count {
                    if Array(input[position..<(position + characters.count)]) == characters {
                        next.insert(position + characters.count)
                    }
                }
            }
            if next.isEmpty { return false }
            reachable = next
        }
        return reachable.contains(input.count)
    }
}
