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
/// Both gaps are closed here. Adjacent tokens whose joined form is a word the
/// caller's dictionary knows are rejoined, which is the only way to tell that
/// まど + ぐち is one word when both halves are also words. Adjacent all-kanji
/// tokens are rejoined whether the dictionary knows them or not, since 東京駅 is
/// a compound no dictionary lists. Particles are identified from the closed set
/// the language actually has, which is how function words are recognised in a
/// language that has a finite list of them.
///
/// The dictionary arrives as a parameter rather than being reached for: this is
/// a pure module, and the word list lives in the app's bundle.
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
    ///
    /// `knownWords` is every form a dictionary lists; pass an empty set to
    /// segment without one, which is what the kanji rule alone can manage.
    public static func tokens(in text: String, knownWords: Set<String>) -> [Token] {
        let raw = rawTokens(in: text)
        let joined = mergeKnownWords(raw, in: text, knownWords: knownWords)
        return merge(joined, in: text).map { range in
            let token = String(text[range])
            return Token(text: token, range: range, role: role(of: token))
        }
    }

    /// The token containing a UTF-16 offset, after merging. What a hover needs.
    public static func token(
        at offset: Int, in text: String, knownWords: Set<String>
    ) -> Token? {
        guard let index = String.Index(
            text.utf16.index(text.utf16.startIndex, offsetBy: offset, limitedBy: text.utf16.endIndex)
                ?? text.utf16.endIndex, within: text)
        else { return nil }
        return tokens(in: text, knownWords: knownWords).first { $0.range.contains(index) }
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

    /// The longest span a merge may produce, in characters.
    ///
    /// ゆうびんきょく is seven. Past eight, a wrong join swallows a clause rather
    /// than a word, and the dictionary is not reliable enough at that length to
    /// be worth the risk.
    private static let maxCompound = 8

    /// Rejoins adjacent tokens whose joined form is a word.
    ///
    /// `NLTokenizer` splits まどぐち into まど + ぐち. Both halves are words, so
    /// no rule about character classes can tell that the pair is one; only a
    /// dictionary can. Longest match wins, so 郵便 + 局 becomes 郵便局 rather
    /// than stopping at the first pair that happens to be listed.
    ///
    /// A particle is never swallowed, even when the span containing it is
    /// itself an entry — では and ではない both are. Particles are what this app
    /// tints and what a learner most needs to see standing apart, so an entry
    /// that hides one costs more than it gives.
    private static func mergeKnownWords(
        _ ranges: [Range<String.Index>], in text: String, knownWords: Set<String>
    ) -> [Range<String.Index>] {
        guard !knownWords.isEmpty else { return ranges }
        var merged: [Range<String.Index>] = []
        var start = ranges.startIndex
        while start < ranges.endIndex {
            var last = start
            if !isParticle(text[ranges[start]]) {
                var end = start
                while end + 1 < ranges.endIndex,
                      ranges[end].upperBound == ranges[end + 1].lowerBound,
                      !isParticle(text[ranges[end + 1]]) {
                    let span = ranges[start].lowerBound..<ranges[end + 1].upperBound
                    guard text[span].count <= maxCompound else { break }
                    end += 1
                    if knownWords.contains(String(text[span])) { last = end }
                }
            }
            merged.append(ranges[start].lowerBound..<ranges[last].upperBound)
            start = last + 1
        }
        return merged
    }

    private static func isParticle(_ slice: Substring) -> Bool {
        particles.contains(String(slice))
    }

    /// Rejoins adjacent all-kanji tokens.
    ///
    /// Two kanji words touching with nothing between them are a compound in
    /// almost all running prose — Japanese puts a particle between separate
    /// nouns. Merging is capped at six characters, past which the risk of
    /// swallowing a real boundary outgrows the benefit.
    ///
    /// Kana runs are not merged here whatever they spell: は and を are kana
    /// too, and a rule about character classes would swallow the particles this
    /// app most wants to keep separate. Kana compounds are the dictionary's job.
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
