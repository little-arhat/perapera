import SwiftUI
import FluentCore

/// Renders text with optional furigana above its kanji.
///
/// Readings are hidden by default. A learner who always sees them never learns
/// to read the kanji, so the reveal is a deliberate act — and the layout
/// reserves the ruby line's height either way, so revealing doesn't make the
/// whole page jump.
struct RubyText: View {
    let annotated: String
    let showFurigana: Bool
    var size: CGFloat = 22

    @Environment(\.palette) private var palette
    @Environment(\.textScale) private var scale
    @Environment(AppModel.self) private var model

    var body: some View {
        // Plain text with no readings needs none of the machinery, and a real
        // SwiftUI Text composes better (Dynamic Type, accessibility, layout).
        if !Furigana.hasAnnotations(annotated) {
            Text(annotated)
                .font(.system(size: scale.size(size)))
                .selectableIf(scale.selectable)
        } else {
            RubyTextView(
                annotated: annotated,
                showFurigana: showFurigana,
                fontSize: scale.size(size),
                color: NSColor(palette.emphasizedText),
                rubyColor: NSColor(palette.secondaryText),
                selectable: scale.selectable,
                highlightWords: model.highlightWords,
                availableWidth: 0
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    /// `.textSelection` takes two different types, so it cannot be chosen with
    /// a ternary. This branches instead.
    @ViewBuilder
    func selectableIf(_ enabled: Bool) -> some View {
        if enabled {
            textSelection(.enabled)
        } else {
            textSelection(.disabled)
        }
    }
}

/// The furigana toggle. Small, always in the same place, so it becomes muscle
/// memory rather than a hunt.
struct FuriganaToggle: View {
    @Binding var isOn: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        Button { isOn.toggle() } label: {
            Label(isOn ? "Hide readings" : "Show readings",
                  systemImage: isOn ? "eye.slash" : "eye")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("f", modifiers: [.command])
        .help("⌘F — readings stay hidden by default so reading kanji stays a real test")
    }
}
