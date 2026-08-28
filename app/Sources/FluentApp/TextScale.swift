import SwiftUI

/// How large target-language text is drawn, and whether it can be selected.
///
/// A single scale factor in the environment rather than a size argument at each
/// call site: sizes were hardcoded per view (22pt prompts, 18pt options), so
/// changing them meant hunting through every file and getting it inconsistent.
/// Views ask for a *role* size and the scale is applied for them.
struct TextScale {
    /// 0.7 to 2.0. Multiplies every target-language size.
    var factor: Double = 1.0
    /// Selectable text is useful for dictionary lookups and terrible for
    /// answering, where a stray drag highlights half the question. So it is a
    /// choice, not a default.
    var selectable: Bool = false

    static let minimum = 0.7
    static let maximum = 2.0
    static let step = 0.1

    func size(_ base: CGFloat) -> CGFloat { base * factor }

    /// Reading column width for a given base.
    ///
    /// Grows with the text, but at roughly half the rate and capped at 1.6x.
    /// The first version scaled by (f²+f)/2, which was derived for Japanese
    /// where a character is about one em. Mixed prose is not: English runs near
    /// half an em, so a column sized to hold 35 kana held 75 latin characters —
    /// well past comfortable measure. Sub-linear and clamped keeps both scripts
    /// inside a readable line at every size.
    func width(_ base: CGFloat) -> CGFloat {
        let growth = 1 + (factor - 1) * 0.6
        return base * min(1.6, max(0.85, growth))
    }
}

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue = TextScale()
}

extension EnvironmentValues {
    var textScale: TextScale {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

/// On-screen text sizing. The keyboard shortcuts live in the app's menu
/// commands so they work on every screen; these are the discoverable version.
///
/// Deliberately two fixed buttons and no Reset: a control that appears only
/// when the size is non-default shifts everything beside it each time you cross
/// the boundary. ⌘0 still resets, and stepping back by hand is barely slower.
struct TextSizeControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            Button { model.adjustTextSize(by: -TextScale.step) } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .disabled(model.textSizeFactor <= TextScale.minimum + 0.001)

            Button { model.adjustTextSize(by: TextScale.step) } label: {
                Image(systemName: "textformat.size.larger")
            }
            .disabled(model.textSizeFactor >= TextScale.maximum - 0.001)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.secondaryText)
        .help("⌘+ / ⌘− to resize, ⌘0 to reset")
    }
}

/// Menu commands, so the shortcuts work regardless of what is on screen.
struct TextSizeCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Bigger Text") { model.adjustTextSize(by: TextScale.step) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller Text") { model.adjustTextSize(by: -TextScale.step) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { model.resetTextSize() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
        }
    }
}

/// Toggles word highlighting on hover.
struct WordHighlightToggle: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        Button { model.highlightWords.toggle() } label: {
            Label(model.highlightWords ? "Words on" : "Words off",
                  systemImage: model.highlightWords
                      ? "character.cursor.ibeam" : "character")
                .font(.caption)
                .foregroundStyle(model.highlightWords
                                 ? palette.accent : palette.secondaryText)
        }
        .buttonStyle(.plain)
        .help("Highlight the word under the pointer; click to copy it")
    }
}

/// Toggles whether target-language text can be selected and copied.
struct SelectionToggle: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        Button { model.textSelectable.toggle() } label: {
            Label(model.textSelectable ? "Selection on" : "Selection off",
                  systemImage: model.textSelectable
                      ? "selection.pin.in.out" : "hand.tap")
                .font(.caption)
                .foregroundStyle(model.textSelectable
                                 ? palette.accent : palette.secondaryText)
        }
        .buttonStyle(.plain)
        .help("Allow selecting text to copy it for dictionary lookups")
    }
}
