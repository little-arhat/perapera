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

    private var segments: [Furigana.Segment] { Furigana.parse(annotated) }
    private var scaled: CGFloat { scale.size(size) }
    private var rubySize: CGFloat { scaled * 0.45 }

    var body: some View {
        if !Furigana.hasAnnotations(annotated) {
            Text(annotated)
                .font(.system(size: scaled))
                .selectableIf(scale.selectable)
        } else {
            FlowLayout(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    VStack(spacing: 1) {
                        Text(segment.reading ?? " ")
                            .font(.system(size: rubySize))
                            .foregroundStyle(palette.secondaryText)
                            .opacity(showFurigana && segment.reading != nil ? 1 : 0)
                        Text(segment.base)
                            .font(.system(size: scaled))
                            .selectableIf(scale.selectable)
                    }
                    // Height is reserved whether or not the reading shows, so
                    // toggling furigana never reflows the page.
                    .frame(minHeight: scaled + rubySize + 1, alignment: .bottom)
                }
            }
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
