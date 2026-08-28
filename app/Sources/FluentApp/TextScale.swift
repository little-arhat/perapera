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

/// The ⌘+ / ⌘- / ⌘0 controls, and a matching on-screen pair.
struct TextSizeControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 2) {
            Button { model.adjustTextSize(by: -TextScale.step) } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(model.textSizeFactor <= TextScale.minimum + 0.001)

            Button { model.adjustTextSize(by: TextScale.step) } label: {
                Image(systemName: "textformat.size.larger")
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(model.textSizeFactor >= TextScale.maximum - 0.001)

            // Only offered once it would do something, so it is not permanent
            // clutter.
            if abs(model.textSizeFactor - 1.0) > 0.001 {
                Button("Reset") { model.resetTextSize() }
                    .keyboardShortcut("0", modifiers: .command)
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.secondaryText)
        .help("⌘+ / ⌘− to resize, ⌘0 to reset")
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
