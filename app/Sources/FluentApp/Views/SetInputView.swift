import SwiftUI
import FluentCore

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

    /// Per-item verdicts, once answered.
    private var verdicts: [Bool?] {
        guard isLocked else { return Array(repeating: nil, count: items.count) }
        return Grader.setVerdicts(items, .texts(draft.texts))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items.indices, id: \.self) { index in
                row(index)
            }
        }
        .onAppear {
            if draft.texts.count != items.count {
                draft.texts = Array(repeating: "", count: items.count)
            }
        }
    }

    private func row(_ index: Int) -> some View {
        let item = items[index]
        let verdict = verdicts[index]

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index + 1).")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 24, alignment: .trailing)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        RubyText(annotated: item.prompt,
                                 showFurigana: model.showFurigana, size: 18)
                            .foregroundStyle(palette.emphasizedText)
                        if let hint = item.hint, !hint.isEmpty {
                            Text("(\(hint))")
                                .font(.callout)
                                .foregroundStyle(palette.secondaryText)
                                .selectableIf(scale.selectable)
                        }
                    }

                    HStack(spacing: 8) {
                        field(index)
                            .frame(maxWidth: 320)

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
                            Text(model.showFurigana
                                 ? Furigana.parenthesized(explanation)
                                 : Furigana.stripped(explanation))
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                                .selectableIf(scale.selectable)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface.opacity(0.6), in: .rect(cornerRadius: 8))
    }

    @ViewBuilder
    private func field(_ index: Int) -> some View {
        let binding = Binding(
            get: { draft.texts.indices.contains(index) ? draft.texts[index] : "" },
            set: { value in
                if draft.texts.count != items.count {
                    draft.texts = Array(repeating: "", count: items.count)
                }
                draft.texts[index] = value
            })

        if useKana {
            KanaTextField(text: binding, compact: true)
        } else {
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 17))
        }
    }
}
