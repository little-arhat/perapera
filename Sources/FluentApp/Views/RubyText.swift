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
    /// Shrink to the content instead of filling the width offered. For inline
    /// words — reorder tokens — not for anything that wraps.
    var hugsContent: Bool = false

    @Environment(\.palette) private var palette
    @Environment(\.textScale) private var scale
    @Environment(AppModel.self) private var model

    @State private var tappedWord: String?
    @State private var wordRect: CGRect = .zero

    var body: some View {
        // Plain text with no readings needs none of the machinery, and a real
        // SwiftUI Text composes better (Dynamic Type, accessibility, layout).
        if !Furigana.hasAnnotations(annotated) {
            Text(annotated)
                .font(.system(size: scale.size(size)))
                .selectableIf(scale.selectable)
                .fixedSize(horizontal: hugsContent, vertical: false)
        } else {
            RubyTextView(
                annotated: annotated,
                showFurigana: showFurigana,
                fontSize: scale.size(size),
                color: NSColor(palette.emphasizedText),
                rubyColor: NSColor(palette.secondaryText),
                selectable: scale.selectable,
                highlightWords: model.highlightWords,
                availableWidth: 0,
                // Only offered when word highlighting is on: without it there
                // is no indication a word is a target, and a click that opens a
                // menu out of nowhere is a surprise rather than a feature.
                onWordTapped: model.highlightWords
                    ? { word, rect in
                        tappedWord = word
                        wordRect = rect
                    }
                    : nil,
                hugsContent: hugsContent
            )
            .fixedSize(horizontal: hugsContent, vertical: true)
            .popover(
                isPresented: Binding(
                    get: { tappedWord != nil },
                    set: { if !$0 { tappedWord = nil } }),
                attachmentAnchor: .rect(.rect(wordRect)),
                arrowEdge: .top
            ) {
                if let tappedWord {
                    WordActionsPopover(word: tappedWord) { self.tappedWord = nil }
                }
            }
        }
    }
}

/// Markdown prose that may carry furigana — a lesson preamble, an explanation.
///
/// Uses the same Core Text canvas as RubyText so readings are real ruby rather
/// than 切符（きっぷ）parentheticals. Parentheticals were the earlier approach and
/// changed the text's *length*, so toggling readings reflowed the paragraph and
/// moved everything below it.
struct MarkdownRubyText: View {
    let markdown: String
    let showFurigana: Bool
    var size: CGFloat = 15

    @Environment(\.palette) private var palette
    @Environment(\.textScale) private var scale
    @Environment(AppModel.self) private var model

    @State private var tappedWord: String?
    @State private var wordRect: CGRect = .zero

    var body: some View {
        RubyTextView(
            annotated: markdown,
            showFurigana: showFurigana,
            fontSize: scale.size(size),
            color: NSColor(palette.bodyText),
            rubyColor: NSColor(palette.secondaryText),
            selectable: scale.selectable,
            highlightWords: model.highlightWords,
            availableWidth: 0,
            isMarkdown: true
        )
        .fixedSize(horizontal: false, vertical: true)
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
