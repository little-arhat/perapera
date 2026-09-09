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

    @State private var annotated: String?

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
                .onChange(of: model.scratchText) { annotated = nil }

            HStack(spacing: 12) {
                Button {
                    annotated = JapaneseReadings.annotate(model.scratchText)
                } label: {
                    Label("Read it", systemImage: "text.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .disabled(model.scratchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty)

                FuriganaToggle(isOn: $model.showFurigana)

                Spacer()

                Button("Clear") {
                    model.scratchText = ""
                    annotated = nil
                }
                .disabled(model.scratchText.isEmpty)
            }

            if let annotated {
                reading(annotated)
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
                RubyText(annotated: annotated, showFurigana: model.showFurigana)
                    .frame(maxWidth: scale.prose(720), alignment: .leading)

                // The tokenizer splits some compounds it should not -- 新幹線
                // comes back as 新 + 幹線 -- so the readings are right more often
                // than the word boundaries are. Saying so beats a learner
                // quietly memorising a split that is not a word.
                Text("Readings come from the system tokenizer. It occasionally splits a "
                     + "compound in the wrong place, so treat the word boundaries as a "
                     + "hint rather than an authority.")
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
