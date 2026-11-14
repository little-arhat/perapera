import SwiftUI
import PeraperaCore

/// Reading practice on text the learner brought themselves.
///
/// A lesson is text the app chose. This is the other half: a menu photographed
/// in Tokyo, a line from a manga, a sign someone could not read. Paste it, get
/// readings, click a word for its meaning, keep the ones worth keeping.
///
/// Readings come from the system tokenizer rather than the model, so this costs
/// nothing and works on a plane.
struct ScratchPadView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.textScale) private var scale

    /// The last text read, with its annotation.
    ///
    /// Held as a pair and shown only while `source` still matches the editor,
    /// so editing hides a stale reading by itself.
    ///
    /// It was a lone `annotated` string cleared from `onChange(of: scratchText)`,
    /// which left putting a remembered text back dependent on an ordering
    /// nothing guarantees: that action sets the text *and* renders it, and a
    /// change handler running afterwards would wipe what it just rendered.
    /// Deriving what to show from the two values cannot go wrong in either
    /// order.
    private struct Rendering: Equatable {
        let source: String
        let annotated: String
    }

    @State private var rendered: Rendering?

    private var shown: Rendering? {
        rendered.flatMap { $0.source == model.scratchText ? $0 : nil }
    }

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 14) {
            header

            TextEditor(text: $model.scratchText)
                .font(.system(size: scale.size(17)))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(palette.surface, in: .rect(cornerRadius: 8))
                .frame(minHeight: 120, maxHeight: 200)

            HStack(spacing: 12) {
                Button { read() } label: {
                    Label("Read it", systemImage: "text.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .disabled(isBlank)

                FuriganaToggle(isOn: $model.showFurigana)
                SeparatorToggle(isOn: $model.showWordSeparators)

                Spacer()

                Button("Clear") {
                    model.scratchText = ""
                    rendered = nil
                }
                .disabled(model.scratchText.isEmpty)
            }
            // The spacing is part of the rendering, so flipping it re-renders
            // what is on screen rather than waiting to be asked again.
            .onChange(of: model.showWordSeparators) { if shown != nil { render() } }

            if !model.scratchHistory.entries.isEmpty { history }

            if let shown {
                reading(shown.annotated)
            } else {
                Text("Paste Japanese above and press Read it. Readings are computed on "
                     + "this Mac, so it works offline and costs nothing.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { model.persistScratch() }
    }

    private var isBlank: Bool {
        model.scratchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Renders what is in the editor. Separate from `read()` because flipping a
    /// display switch is not reading the text again.
    private func render() {
        let known = model.dictionary.knownWords
        let text = model.scratchText
        let spaced = model.showWordSeparators
            ? JapaneseText.separated(text, knownWords: known)
            : text
        rendered = Rendering(
            source: text,
            annotated: JapaneseReadings.annotate(spaced, knownWords: known))
    }

    private func read() {
        render()
        model.recordScratchRead(model.scratchText)
    }

    /// What the pad has read before.
    ///
    /// The pad held one text and overwrote it, so a menu read last week was
    /// gone the moment the next one was pasted. These are the learner's own
    /// materials, which is the one thing a lesson cannot supply.
    private var history: some View {
        CollapsibleSection(
            title: "Read before",
            summary: "^[\(model.scratchHistory.entries.count) text](inflect: true)",
            storageKey: "scratch.history",
            expandedByDefault: false
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.scratchHistory.entries) { entry in
                    row(entry)
                    if entry.id != model.scratchHistory.entries.last?.id {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: scale.prose(720), alignment: .leading)
            .background(palette.surface, in: .rect(cornerRadius: 8))
        }
    }

    private func row(_ entry: ScratchEntry) -> some View {
        HStack(spacing: 10) {
            Button { open(entry) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.summary)
                        .font(.system(size: scale.size(14)))
                        .foregroundStyle(palette.emphasizedText)
                        .lineLimit(1)
                    Text("^[\(entry.characterCount) character](inflect: true) · "
                         + "\(entry.readAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Put this back in the pad")

            Button { model.forgetScratch(id: entry.id) } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Forget this text")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Puts a text back in the pad, already read: it was read once, and asking
    /// for it again would be asking for work the app has already done.
    private func open(_ entry: ScratchEntry) {
        model.scratchText = entry.text
        model.persistScratch()
        render()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Scratch pad")
                .font(.title2)
                .foregroundStyle(palette.emphasizedText)
            Text("Your own text, with readings. Click a word for its meaning, to save "
                 + "it, or to look it up.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
        }
    }

    private func reading(_ annotated: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Word actions are forced on here rather than following the
                // preference: looking a word up is what this screen is for, and
                // the preference defaults to off.
                RubyText(annotated: annotated, showFurigana: model.showFurigana,
                         wordActions: true)
                    .frame(maxWidth: scale.prose(720), alignment: .leading)

                // The tokenizer splits some compounds it should not -- 新幹線
                // comes back as 新 + 幹線 -- so the readings are right more often
                // than the word boundaries are. Saying so beats a learner
                // quietly memorising a split that is not a word.
                Text("Click any word for its meaning, to save it, or to look it up. "
                     + "Readings come from the system tokenizer, which occasionally "
                     + "splits a compound in the wrong place, so treat the word "
                     + "boundaries as a hint rather than an authority.")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.top, 6)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: .rect(cornerRadius: 10))
        }
    }
}
