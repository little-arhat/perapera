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
            if let reading, reading != token {
                result += "\(token)[\(reading)]"
            } else {
                result += token
            }
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }

    /// Every token that contains a kanji, with its kana reading.
    public static func readings(in text: String) -> [(Range<String.Index>, String?)] {
        guard !text.isEmpty else { return [] }
        let cf = text as CFString
        let full = CFRangeMake(0, CFStringGetLength(cf))
        guard let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault, cf, full,
            kCFStringTokenizerUnitWordBoundary,
            Locale(identifier: "ja") as CFLocale)
        else { return [] }

        var found: [(Range<String.Index>, String?)] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let cfRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard let range = Range(NSRange(location: cfRange.location,
                                            length: cfRange.length), in: text)
            else { continue }
            let token = String(text[range])
            guard containsKanji(token) else { continue }

            let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            found.append((range, latin.flatMap(hiragana(fromLatin:))))
        }
        return found
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
