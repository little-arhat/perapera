import Foundation

/// Reading annotations over kanji.
///
/// Written inline, in the convention Anki and most Japanese tooling use:
/// `切符[きっぷ]を2枚[まい]ください`. One field rather than a parallel array of
/// readings, because two collections that must stay index-aligned are two
/// chances to desync — and a misaligned reading is worse than none.
///
/// Furigana is *withheld* by default in the app. A learner who always sees the
/// reading never learns to read the kanji, so revealing it is a deliberate act.
public enum Furigana {
    /// One run of text, with the reading that belongs over it.
    public struct Segment: Equatable, Sendable {
        public let base: String
        /// `nil` for text that needs no annotation (kana, punctuation, latin).
        public let reading: String?

        public init(base: String, reading: String?) {
            self.base = base
            self.reading = reading
        }
    }

    /// Splits annotated text into segments.
    ///
    /// Unmatched brackets are left as literal text rather than swallowed: a
    /// generator that emits `[` for some other reason should produce visible
    /// oddity, not silently vanishing characters.
    public static func parse(_ annotated: String) -> [Segment] {
        var segments: [Segment] = []
        var plain = ""
        var index = annotated.startIndex

        func flushPlain() {
            if !plain.isEmpty {
                segments.append(Segment(base: plain, reading: nil))
                plain = ""
            }
        }

        while index < annotated.endIndex {
            let character = annotated[index]
            guard character == "[" else {
                plain.append(character)
                index = annotated.index(after: index)
                continue
            }

            // A reading annotates the run of kanji immediately before it.
            guard
                let close = annotated[index...].firstIndex(of: "]"),
                case let reading = String(annotated[annotated.index(after: index)..<close]),
                !reading.isEmpty,
                case let baseLength = trailingKanjiCount(of: plain),
                baseLength > 0
            else {
                plain.append(character)
                index = annotated.index(after: index)
                continue
            }

            let base = String(plain.suffix(baseLength))
            plain.removeLast(baseLength)
            flushPlain()
            segments.append(Segment(base: base, reading: reading))
            index = annotated.index(after: close)
        }

        flushPlain()
        return segments
    }

    /// The text with every annotation removed — what the learner reads when
    /// furigana is off, and what gets compared when grading.
    public static func stripped(_ annotated: String) -> String {
        parse(annotated).map(\.base).joined()
    }

    /// The text fully in kana — annotated runs replaced by their readings.
    /// Useful for speech, where a voice benefits from the intended reading of an
    /// ambiguous kanji.
    public static func reading(_ annotated: String) -> String {
        parse(annotated).map { $0.reading ?? $0.base }.joined()
    }

    /// Readings as parentheticals: 切符（きっぷ）.
    ///
    /// For places that render Markdown — a lesson preamble, a feedback comment —
    /// where ruby cannot be drawn but the reading is still worth having. The
    /// alternative is stripping it, which throws away the one thing a beginner
    /// most needs from a kanji they have not met.
    ///
    /// Full-width brackets on purpose: 「切符(きっぷ)」 in half-width reads as
    /// an aside in latin text, while （）is the Japanese convention and sits
    /// correctly against CJK glyphs.
    public static func parenthesized(_ annotated: String) -> String {
        parse(annotated)
            .map { segment in
                guard let reading = segment.reading else { return segment.base }
                return "\(segment.base)（\(reading)）"
            }
            .joined()
    }

    /// Whether anything here is annotated, so a view can skip the ruby layout
    /// entirely for plain text.
    public static func hasAnnotations(_ annotated: String) -> Bool {
        parse(annotated).contains { $0.reading != nil }
    }

    /// How many trailing characters of `text` are kanji.
    ///
    /// The reading covers the kanji run only: in `買[か]います` the reading
    /// belongs over 買, not over 買います. Counting backwards from the bracket
    /// gets that right without the generator having to mark boundaries.
    private static func trailingKanjiCount(of text: String) -> Int {
        var count = 0
        for character in text.reversed() {
            guard character.unicodeScalars.allSatisfy(isKanji) else { break }
            count += 1
        }
        return count
    }

    private static func isKanji(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,   // CJK Unified Ideographs
             0x3400...0x4DBF,   // Extension A
             0xF900...0xFAFF,   // Compatibility Ideographs
             0x3005:            // 々, the repetition mark
            true
        default:
            false
        }
    }
}
