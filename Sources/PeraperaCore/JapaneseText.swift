import Foundation
import NaturalLanguage

/// Segmenting and classifying Japanese, for hovering, tinting and readings.
///
/// `NLTokenizer` is the only Japanese segmenter macOS exposes, and it splits
/// compounds: 新幹線 comes back as 新 + 幹線, 東京駅 as 東京 + 駅. It also offers
/// no part of speech at all — `NLTagger`'s `.lexicalClass` returns `OtherWord`
/// for every Japanese token, verified on macOS 15 — so role has to come from
/// somewhere else.
///
/// Both gaps are closed here without a dictionary. Adjacent all-kanji tokens are
/// rejoined, which is the compound case that misleads a learner most. Particles
/// are identified from the closed set the language actually has, which is how
/// function words are recognised in a language that has a finite list of them.
public enum JapaneseText {
    public enum Role: Equatable, Sendable {
        /// は, を, に and the rest: the words that mark what everything else is doing.
        case particle
        /// Anything carrying meaning rather than marking structure.
        case content
        /// Digits, Latin, punctuation, whitespace.
        case other
    }

    public struct Token: Equatable, Sendable {
        public let text: String
        public let range: Range<String.Index>
        public let role: Role

        public init(text: String, range: Range<String.Index>, role: Role) {
            self.text = text
            self.range = range
            self.role = role
        }
    }

    /// Japanese particles, which are a closed class.
    ///
    /// Longest first, so か is never matched where から was meant. This is a list
    /// rather than a model because the language provides a list: new particles do
    /// not get coined, and a lookup is exactly right for a set that cannot grow.
    public static let particles: [String] = [
        "について", "によって", "として", "ばかり", "くらい", "ぐらい", "だけ",
        "しか", "など", "ながら", "から", "まで", "より", "ほど", "こそ", "さえ",
        "でも", "とか", "のに", "ので", "けど", "でわ", "には", "へは", "とは",
        "は", "が", "を", "に", "で", "と", "へ", "も", "の", "や", "ね", "よ",
        "か", "な", "ぞ", "ぜ", "わ", "さ",
    ]

    /// Every token, with compounds rejoined and roles assigned.
    public static func tokens(in text: String) -> [Token] {
        merge(rawTokens(in: text), in: text).map { range in
            let token = String(text[range])
            return Token(text: token, range: range, role: role(of: token))
        }
    }

    /// The token containing a UTF-16 offset, after merging. What a hover needs.
    public static func token(at offset: Int, in text: String) -> Token? {
        guard let index = String.Index(
            text.utf16.index(text.utf16.startIndex, offsetBy: offset, limitedBy: text.utf16.endIndex)
                ?? text.utf16.endIndex, within: text)
        else { return nil }
        return tokens(in: text).first { $0.range.contains(index) }
    }

    public static func role(of token: String) -> Role {
        if particles.contains(token) { return .particle }
        let kana = token.unicodeScalars.allSatisfy { (0x3040...0x30FF).contains($0.value) }
        let meaningful = token.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)     // kana
                || JapaneseReadings.containsKanji(String(scalar))
        }
        guard meaningful else { return .other }
        // A one-kana token that is not in the particle list is still structural
        // far more often than not, but guessing would tint the wrong things.
        _ = kana
        return .content
    }

    private static func rawTokens(in text: String) -> [Range<String.Index>] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(.japanese)
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
    }

    /// Rejoins adjacent all-kanji tokens.
    ///
    /// Two kanji words touching with nothing between them are a compound in
    /// almost all running prose — Japanese puts a particle between separate
    /// nouns. Merging is capped at six characters, past which the risk of
    /// swallowing a real boundary outgrows the benefit.
    ///
    /// Kana compounds (まどぐち splits to まど + ぐち) are left alone: は and を
    /// are kana too, and merging kana runs would swallow the particles this app
    /// most wants to keep separate. Fixing those needs a real dictionary.
    private static func merge(
        _ ranges: [Range<String.Index>], in text: String
    ) -> [Range<String.Index>] {
        var merged: [Range<String.Index>] = []
        for range in ranges {
            guard let last = merged.last,
                  last.upperBound == range.lowerBound,
                  isAllKanji(text[last]), isAllKanji(text[range]),
                  text[last.lowerBound..<range.upperBound].count <= 6
            else {
                merged.append(range)
                continue
            }
            merged[merged.count - 1] = last.lowerBound..<range.upperBound
        }
        return merged
    }

    private static func isAllKanji(_ slice: Substring) -> Bool {
        !slice.isEmpty && slice.unicodeScalars.allSatisfy {
            JapaneseReadings.containsKanji(String($0))
        }
    }
}
