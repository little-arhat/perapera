import SwiftUI
import PeraperaCore

/// A numbered drill: several short items under one instruction.
///
/// The shape a textbook uses — "Fill the gaps", then a, b, c… — because
/// repetition on one point is what turns a rule you know into one you use
/// without thinking. Answered together, graded item by item.
struct SetInputView: View {
    let items: [Exercise.SetItem]
    @Binding var draft: ExerciseDraft
    let isLocked: Bool
    let useKana: Bool

    @Environment(\.palette) private var palette
    @Environment(\.textScale) private var scale
    @Environment(AppModel.self) private var model

    /// Cues asked for, by item. A cue printed beside every item is read before
    /// the item is, and for an easy one it is the answer; behind a button it
    /// costs a click, which is what makes it a hint.
    @State private var hintsShown: Set<Int> = []

    /// Per-item verdicts, once answered.
    private var verdicts: [Bool?] {
        guard isLocked else { return Array(repeating: nil, count: items.count) }
        return Grader.setVerdicts(items, .texts(draft.texts))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                row(index)
            }
        }
        // A numbered drill is a list of short answers, not a table: at the full
        // card width each row is a 360pt field in a 1000pt band. Scaled, so the
        // rows grow with the text rather than pinning it at one size.
        .frame(maxWidth: scale.width(480), alignment: .leading)
        .onAppear {
            // Grow to fit without discarding what is already there: a restored
            // answer arrives before this runs, and replacing the array
            // wholesale would throw it away.
            if draft.texts.count < items.count {
                draft.texts += Array(repeating: "", count: items.count - draft.texts.count)
            }
        }
    }

    /// The gutter the number sits in, and what the rest of the row is inset by
    /// so the field lines up under the sentence rather than under the number.
    private let gutter: CGFloat = 26

    private func row(_ index: Int) -> some View {
        let item = items[index]
        let verdict = verdicts[index]

        return VStack(alignment: .leading, spacing: 6) {
            // The number rides with the sentence, not above it: furigana adds
            // a line of height to the prompt, and a top-aligned number floats
            // clear of the text it belongs to.
            HStack(alignment: .center, spacing: 8) {
                Text("\(index + 1).")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: gutter - 8, alignment: .trailing)

                RubyText(annotated: item.prompt,
                         showFurigana: model.showFurigana, size: 18)
                    .foregroundStyle(palette.emphasizedText)
                    .layoutPriority(1)
                if let hint = item.hint, !hint.isEmpty {
                    if isLocked || hintsShown.contains(index) {
                        Text("(\(hint))")
                            .font(.callout)
                            .foregroundStyle(palette.secondaryText)
                            .selectableIf(scale.selectable)
                    } else {
                        Button("hint") { hintsShown.insert(index) }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .help("Show the cue for this item")
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    field(index)
                        .frame(maxWidth: 360)

                    if let verdict {
                        Image(systemName: verdict
                              ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(verdict ? palette.correct : palette.wrong)
                    } else if isLocked {
                        Image(systemName: "person.fill.questionmark")
                            .foregroundStyle(palette.review)
                    }
                }

                // Only shown once answered, and only where it helps.
                if isLocked, verdict == false {
                    Text("→ \(item.acceptedAnswers.first ?? "")")
                        .font(.callout)
                        .foregroundStyle(palette.emphasizedText)
                        .selectableIf(scale.selectable)
                    if let explanation = item.explanation, !explanation.isEmpty {
                        // Wraps rather than running off the card: a sentence
                        // laid out at its ideal width is clipped by the row,
                        // and half an explanation teaches nothing.
                        Text(model.showFurigana
                             ? Furigana.parenthesized(explanation)
                             : Furigana.stripped(explanation))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .selectableIf(scale.selectable)
                    }
                }
            }
            .padding(.leading, gutter)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface.opacity(0.6), in: .rect(cornerRadius: 8))
    }

    @ViewBuilder
    private func field(_ index: Int) -> some View {
        let binding = Binding(
            get: { draft.texts.indices.contains(index) ? draft.texts[index] : "" },
            set: { value in
                if draft.texts.count < items.count {
                    draft.texts += Array(
                        repeating: "", count: items.count - draft.texts.count)
                }
                draft.texts[index] = value
            })

        if useKana {
            KanaTextField(text: binding, compact: true)
                // Per-row identity: without it SwiftUI reuses one field's
                // internal state across rows, which is how answers leaked
                // between exercises before.
                .id(index)
        } else {
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 17))
        }
    }
}
