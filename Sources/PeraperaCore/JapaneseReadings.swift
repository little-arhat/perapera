import Foundation

/// Kana readings for arbitrary Japanese text, computed locally.
///
/// The system tokenizer already knows how to read Japanese: it is what powers
/// the IME and speech. Asking it costs nothing and needs no network, which
/// matters for a scratch pad where the learner pastes whatever they are reading
/// and expects an answer immediately.
///
/// Output uses the same inline convention as the rest of the app, so everything
/// that renders a lesson renders this: `切符[きっぷ]を2枚[まい]ください`.
public enum JapaneseReadings {
    /// Annotates every token containing kanji with its reading.
    ///
    /// Kana, punctuation, numerals and Latin pass through untouched, and so does
    /// the whitespace between tokens: the learner's own line breaks are part of
    /// what they pasted.
    ///
    /// A token is annotated whole, okurigana included — `食べる[たべる]` rather
    /// than `食[た]べる`. Splitting the reading across the stem boundary needs
    /// morphology the tokenizer does not expose, and a whole-word reading is both
    /// correct and what Anki decks use.
    public static func annotate(_ text: String) -> String {
        var result = ""
        var cursor = text.startIndex

        for (range, reading) in readings(in: text) {
            result += text[cursor..<range.lowerBound]
            let token = String(text[range])
            result += annotated(token: token, reading: reading)
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }

    /// One token in `kanji[reading]` form, with its okurigana left outside.
    ///
    /// `Furigana.parse` attaches a reading to the run of kanji immediately
    /// before it, so `目指し[めざし]` is not a reading at all -- the base ends in
    /// kana, the parser finds no kanji run, and the brackets render as literal
    /// text in the middle of the sentence. It has to be `目指[めざ]し`.
    ///
    /// The kana that a token and its reading share at each end are the same
    /// characters, so they can be split off by comparison rather than by
    /// morphology: 輝く/かがやく gives 輝[かがや]く, お誕生日/おたんじょうび gives
    /// お誕生日[たんじょうび] with the お outside.
    ///
    /// When the two do not agree at the edges -- a sound change, or a reading
    /// the tokenizer got wrong -- the token is returned unannotated. A missing
    /// reading is a smaller loss than a wrong one, and far smaller than brackets
    /// on the page.
    static func annotated(token: String, reading: String?) -> String {
        guard let reading, reading != token, !reading.isEmpty else { return token }

        var base = Array(token)
        var kana = Array(reading)
        var prefix = "", suffix = ""

        while let first = base.first, let readingFirst = kana.first,
              !containsKanji(String(first)), first == readingFirst {
            prefix.append(first)
            base.removeFirst()
            kana.removeFirst()
        }
        while let last = base.last, let readingLast = kana.last,
              !containsKanji(String(last)), last == readingLast {
            suffix = String(last) + suffix
            base.removeLast()
            kana.removeLast()
        }

        let core = String(base)
        // The base must be a pure kanji run, or `parse` will not take it.
        guard !core.isEmpty, !kana.isEmpty,
              core.unicodeScalars.allSatisfy({ containsKanji(String($0)) })
        else { return token }
        return "\(prefix)\(core)[\(String(kana))]\(suffix)"
    }

    /// Every token that contains a kanji, with its kana reading.
    ///
    /// Boundaries come from `JapaneseText`, so a compound gets one reading:
    /// 新幹線[しんかんせん] rather than 新[しん]幹線[かんせん].
    ///
    /// The transcription is taken from a single pass over the whole text and
    /// then concatenated within each merged span. Transcribing a span on its own
    /// loses the context the tokenizer reads it in, and 枚 out of context comes
    /// back as ばい where 2枚 gives まい.
    public static func readings(in text: String) -> [(Range<String.Index>, String?)] {
        let latin = transcriptions(in: text)
        return JapaneseText.tokens(in: text)
            .filter { containsKanji($0.text) }
            .map { token in
                let pieces = latin
                    .filter { token.range.lowerBound <= $0.0.lowerBound
                              && $0.0.upperBound <= token.range.upperBound }
                    .map(\.1)
                    .joined()
                return (token.range, pieces.isEmpty ? nil : hiragana(fromLatin: pieces))
            }
    }

    /// Latin transcription of every token, in one pass over the whole string.
    public static func transcriptions(in text: String) -> [(Range<String.Index>, String)] {
        guard !text.isEmpty else { return [] }
        let cf = text as CFString
        let full = CFRangeMake(0, CFStringGetLength(cf))
        guard let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault, cf, full,
            kCFStringTokenizerUnitWordBoundary,
            Locale(identifier: "ja") as CFLocale)
        else { return [] }

        var out: [(Range<String.Index>, String)] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let cfRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard let range = Range(NSRange(location: cfRange.location,
                                            length: cfRange.length), in: text),
                  let piece = CFStringTokenizerCopyCurrentTokenAttribute(
                    tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            else { continue }
            out.append((range, piece))
        }
        return out
    }

    /// The kana reading of one word, or nil if it needs none.
    public static func reading(of word: String) -> String? {
        guard containsKanji(word) else { return nil }
        let pieces = transcriptions(in: word).map(\.1).joined()
        return pieces.isEmpty ? nil : hiragana(fromLatin: pieces)
    }

    /// True if the string holds a CJK ideograph, which is what needs a reading.
    public static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)      // CJK Unified
                || (0x3400...0x4DBF).contains(scalar.value)  // Extension A
                || (0xF900...0xFAFF).contains(scalar.value)  // Compatibility
        }
    }

    /// The tokenizer reports readings as romaji; the learner wants kana.
    static func hiragana(fromLatin latin: String) -> String? {
        let mutable = NSMutableString(string: latin) as CFMutableString
        guard CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
        else { return nil }
        let kana = mutable as String
        // A transform that leaves Latin behind produced no reading worth showing.
        return kana.unicodeScalars.allSatisfy { $0.value >= 0x3040 } ? kana : nil
    }
}
