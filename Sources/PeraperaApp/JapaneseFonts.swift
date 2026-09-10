import AppKit
import PeraperaCore

/// The typefaces on this Mac that can carry a kana drill, and what each one is
/// like in the world.
///
/// Curated rather than "every installed font": the point is to span the styles a
/// learner meets — brush on a noren, mincho on a station sign, rounded on a shop
/// front, textbook in a classroom — not to enumerate what happens to be
/// installed. Each is checked for the glyphs before it is offered, so a font
/// removed by the learner degrades to one fewer style rather than to blank boxes.
enum JapaneseFonts {
    struct Face {
        let family: String
        /// Where a learner meets this shape.
        let context: String
    }

    static let curated: [Face] = [
        .init(family: "Hiragino Sans", context: "screens and signage"),
        .init(family: "Hiragino Mincho ProN", context: "print and formal signs"),
        .init(family: "Hiragino Maru Gothic ProN", context: "shop fronts, friendly notices"),
        .init(family: "YuKyokasho", context: "school textbooks"),
        .init(family: "Klee", context: "textbook handwriting"),
        .init(family: "Toppan Bunkyu Midashi Mincho", context: "display headlines"),
        .init(family: "Tsukushi A Round Gothic", context: "packaging, rounded signage"),
        .init(family: "Yuppy SC", context: "1970s rounded display"),
        .init(family: "Kaiti SC", context: "brush, regular script"),
        .init(family: "Hannotate SC", context: "brush, casual"),
        .init(family: "Libian SC", context: "clerical brush, heavy"),
        .init(family: "Weibei SC", context: "carved-stone brush"),
        .init(family: "Xingkai SC", context: "running brush, hardest to read"),
        .init(family: "Osaka", context: "the old Mac system face"),
        .init(family: "YuMincho", context: "books"),
        .init(family: "BIZ UDGothic", context: "transit and public signage"),
    ]

    /// Those that are installed and can actually draw every character asked of
    /// them. A font that renders a tofu box teaches nothing.
    static func available(rendering characters: [String]) -> [Face] {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return curated.filter { face in
            guard installed.contains(face.family),
                  let font = NSFont(name: face.family, size: 24)
            else { return false }
            return characters.allSatisfy { canRender($0, in: font) }
        }
    }

    static func canRender(_ text: String, in font: NSFont) -> Bool {
        var utf16 = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(font as CTFont, &utf16, &glyphs, utf16.count)
        else { return false }
        return !glyphs.contains(0)
    }

    static func context(for family: String) -> String {
        curated.first { $0.family == family }?.context ?? ""
    }
}
