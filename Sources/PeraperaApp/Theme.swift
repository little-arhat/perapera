import SwiftUI
import PeraperaCore

/// Solarized, by Ethan Schoonover.
///
/// The palette's whole idea is that the eight accents are chosen to work
/// against *either* background, and that the greys are picked so that
/// light and dark are the same design rather than two designs. So the accents
/// below are absolute values, and only the greys flip with the color scheme.
enum Solarized {
    // Greys, darkest to lightest.
    static let base03 = Color(hex: 0x002B36)
    static let base02 = Color(hex: 0x073642)
    static let base01 = Color(hex: 0x586E75)
    static let base00 = Color(hex: 0x657B83)
    static let base0  = Color(hex: 0x839496)
    static let base1  = Color(hex: 0x93A1A1)
    static let base2  = Color(hex: 0xEEE8D5)
    static let base3  = Color(hex: 0xFDF6E3)

    // Accents.
    static let yellow  = Color(hex: 0xB58900)
    static let orange  = Color(hex: 0xCB4B16)
    static let red     = Color(hex: 0xDC322F)
    static let magenta = Color(hex: 0xD33682)
    static let violet  = Color(hex: 0x6C71C4)
    static let blue    = Color(hex: 0x268BD2)
    static let cyan    = Color(hex: 0x2AA198)
    static let green   = Color(hex: 0x859900)
}

/// Semantic roles, resolved against the current color scheme.
///
/// Views name roles, never raw colors -- that is what keeps light and dark from
/// drifting into two separate designs that must each be maintained.
struct Palette {
    let isDark: Bool

    var background: Color      { isDark ? Solarized.base03 : Solarized.base3 }
    var surface: Color         { isDark ? Solarized.base02 : Solarized.base2 }
    var bodyText: Color        { isDark ? Solarized.base0  : Solarized.base00 }
    var emphasizedText: Color  { isDark ? Solarized.base1  : Solarized.base01 }
    var secondaryText: Color   { isDark ? Solarized.base01 : Solarized.base1 }

    var accent: Color   { Solarized.blue }
    var correct: Color  { Solarized.green }
    var wrong: Color    { Solarized.red }
    var warning: Color  { Solarized.yellow }
    var critical: Color { Solarized.orange }
    var review: Color   { Solarized.violet }
    /// Particles: the words that mark what everything else is doing. Cyan is
    /// used for nothing else in running text, so the grammar reads at a glance
    /// without competing with correct/wrong.
    var particle: Color { Solarized.cyan }
    var newItem: Color  { Solarized.cyan }

    /// Severity colors, matching the 🔴/🟡/🟢 vocabulary the tutor already uses
    /// so the app and the transcripts agree.
    func severity(_ name: String) -> Color {
        switch name {
        case "critical": Solarized.red
        case "moderate": Solarized.yellow
        default: Solarized.green
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(isDark: false)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension Appearance {
    /// What to hand SwiftUI. Nil means "don't override", which is what following
    /// the system is: the window chrome and the controls have to move with the
    /// palette or the app is half one theme and half the other.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Supplies the palette, following the system unless the learner has said otherwise.
///
/// The appearance is a parameter rather than something read from the environment:
/// this modifier is applied outside `.environment(model)`, and environment values
/// flow to descendants, not to ancestors. Reading it here compiled and then
/// crashed at launch.
struct SolarizedTheme: ViewModifier {
    let appearance: Appearance
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let palette = Palette(isDark: appearance.isDark(systemIsDark: scheme == .dark))
        content
            .environment(\.palette, palette)
            .background(palette.background)
            .tint(palette.accent)
            .foregroundStyle(palette.bodyText)
    }
}

extension View {
    func solarized(_ appearance: Appearance = .system) -> some View {
        modifier(SolarizedTheme(appearance: appearance))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
