import SwiftUI
import PeraperaCore

/// The input surface for one exercise. One view per shape, chosen by the sum
/// type -- no optionals to unwrap, because the decoder already resolved them.
struct ExerciseInputView: View {
    let exercise: Exercise
    @Binding var draft: ExerciseDraft
    let isLocked: Bool

    @Environment(\.palette) private var palette
    @Environment(AppModel.self) private var model
    /// Which prompt is waiting for an answer, in a matching exercise.
    @State private var pendingLeft: Int?

    private var kanaLanguage: Bool {
        model.snapshot?.databases.learner_profile.learner
            .target_language.lowercased() == "japanese"
    }

    var body: some View {
        Group {
            switch exercise.content {
            case let .multipleChoice(options, _):
                choices(options)
            case .cloze, .digitEntry, .recognition:
                shortText
            case .translation, .freeResponse:
                longText
            case let .reorder(tokens, _):
                reorder(tokens)
            case let .matching(pairs):
                matching(pairs)
            case let .flashcard(front, back):
                flashcard(front: front, back: back)
            case let .set(items):
                SetInputView(items: items, draft: $draft,
                             isLocked: isLocked, useKana: kanaLanguage)
            }
        }
        .disabled(isLocked)
    }

    private func choices(_ options: [String]) -> some View {
        VStack(spacing: 8) {
            ForEach(options.indices, id: \.self) { i in
                Button { draft.choice = i } label: {
                    HStack {
                        // Ruby, not raw markup. Options carry furigana like any
                        // other target-language text, and rendering them as
                        // plain strings leaked 漢字[かんじ] into the UI.
                        RubyText(annotated: options[i],
                                 showFurigana: model.showFurigana, size: 18)
                        Spacer()
                        if draft.choice == i {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        draft.choice == i ? palette.accent.opacity(0.15) : palette.surface,
                        in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var shortText: some View {
        if usesKana {
            KanaTextField(text: $draft.text)
        } else {
            TextField("Your answer", text: $draft.text)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .padding(14)
                .background(palette.surface, in: .rect(cornerRadius: 10))
        }
    }

    /// Kana input is for producing the target language, not for a digit answer
    /// or a translation written in the learner's own language.
    private var usesKana: Bool {
        guard kanaLanguage else { return false }
        switch exercise.content {
        case .digitEntry: return false
        case .cloze, .recognition: return true
        default: return false
        }
    }

    private var longText: some View {
        TextEditor(text: $draft.text)
            .font(.system(size: 18))
            .scrollContentBackground(.hidden)
            .frame(minHeight: 120)
            .padding(10)
            .background(palette.surface, in: .rect(cornerRadius: 10))
    }

    /// Tap tokens in order to build the sentence; tap a placed token to take it
    /// back. Shown in a stable shuffled order so the display itself is not a hint.
    private func reorder(_ tokens: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            FlowLayout(spacing: 8) {
                ForEach(draft.order, id: \.self) { i in
                    Button {
                        draft.order.removeAll { $0 == i }
                    } label: {
                        token(tokens[i], filled: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(palette.surface.opacity(0.5), in: .rect(cornerRadius: 10))

            Divider()

            FlowLayout(spacing: 8) {
                ForEach(shuffledIndices(count: tokens.count), id: \.self) { i in
                    if !draft.order.contains(i) {
                        Button { draft.order.append(i) } label: {
                            token(tokens[i], filled: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func token(_ text: String, filled: Bool) -> some View {
        RubyText(annotated: text, showFurigana: model.showFurigana, size: 18,
                 hugsContent: true)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(filled ? palette.accent.opacity(0.18) : palette.surface,
                        in: .rect(cornerRadius: 8))
    }

    /// A deterministic shuffle keyed by the exercise id: stable across redraws
    /// (so tokens don't jump while you think) but not the generated order (so
    /// the tokens as supplied aren't the answer).
    private func shuffledIndices(count: Int) -> [Int] {
        var generator = SeededGenerator(seed: exercise.id.hashValue)
        return Array(0..<count).shuffled(using: &generator)
    }

    /// Tap a prompt, then tap its answer.
    ///
    /// This was a `Picker` per row, and a `Picker` cannot host ruby, so every
    /// answer in the menu had its readings stripped — the one exercise type
    /// where the learner is reading answers rather than writing them, and the
    /// readings were the part that got dropped. Chips are ordinary views, so
    /// both sides render like the rest of the lesson.
    private func matching(_ pairs: [Exercise.Pair]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(pairs.indices, id: \.self) { i in
                let assigned = matchIndex(i, count: pairs.count)
                HStack(spacing: 10) {
                    RubyText(annotated: pairs[i].left,
                             showFurigana: model.showFurigana, size: 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if assigned >= 0, pairs.indices.contains(assigned) {
                        RubyText(annotated: pairs[assigned].right,
                                 showFurigana: model.showFurigana, size: 16,
                                 hugsContent: true)
                        Button {
                            binding(for: i, count: pairs.count).wrappedValue = -1
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(palette.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .help("Unmatch")
                    } else {
                        Text(pendingLeft == i ? "now pick its answer" : "tap to match")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    pendingLeft == i ? palette.accent.opacity(0.15) : palette.surface,
                    in: .rect(cornerRadius: 8))
                .contentShape(.rect)
                .onTapGesture { pendingLeft = pendingLeft == i ? nil : i }
            }

            Text("Answers")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .padding(.top, 4)

            // A plain wrapping row of chips. Used answers stay visible but dimmed,
            // so the learner can see what is left without the list reordering
            // under them.
            FlowRow(spacing: 8) {
                ForEach(pairs.indices, id: \.self) { j in
                    let used = isUsed(j, count: pairs.count)
                    Button {
                        guard let left = pendingLeft else { return }
                        assign(right: j, to: left, count: pairs.count)
                        pendingLeft = nil
                    } label: {
                        RubyText(annotated: pairs[j].right,
                                 showFurigana: model.showFurigana, size: 16,
                                 hugsContent: true)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(palette.surface, in: .rect(cornerRadius: 8))
                            .opacity(used ? 0.35 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(used || pendingLeft == nil)
                    .help(pendingLeft == nil ? "Pick a prompt first" : "Match this answer")
                }
            }
        }
    }

    private func matchIndex(_ index: Int, count: Int) -> Int {
        draft.matches.count == count ? draft.matches[index] : -1
    }

    private func isUsed(_ right: Int, count: Int) -> Bool {
        draft.matches.count == count && draft.matches.contains(right)
    }

    /// One answer belongs to one prompt, so assigning it takes it back from
    /// wherever it was.
    private func assign(right: Int, to left: Int, count: Int) {
        if draft.matches.count != count {
            draft.matches = Array(repeating: -1, count: count)
        }
        for (index, value) in draft.matches.enumerated() where value == right {
            draft.matches[index] = -1
        }
        draft.matches[left] = right
    }

    private func binding(for index: Int, count: Int) -> Binding<Int> {
        Binding(
            get: {
                draft.matches.count == count ? draft.matches[index] : -1
            },
            set: { value in
                if draft.matches.count != count {
                    draft.matches = Array(repeating: -1, count: count)
                }
                draft.matches[index] = value
            }
        )
    }

    /// Self-rating, because a flashcard's answer lives in the learner's head and
    /// only they can say whether it was there.
    private func flashcard(front: String, back: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            RubyText(annotated: front, showFurigana: model.showFurigana, size: 34)
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(palette.surface, in: .rect(cornerRadius: 12))

            if draft.rating != nil {
                RubyText(annotated: back, showFurigana: model.showFurigana, size: 20)
                    .foregroundStyle(palette.emphasizedText)
            }

            Text("How well did you know it?")
                .font(.callout).foregroundStyle(palette.secondaryText)

            HStack(spacing: 8) {
                ForEach(0...5, id: \.self) { rating in
                    Button { draft.rating = rating } label: {
                        Text("\(rating)")
                            .frame(width: 40, height: 36)
                            .background(
                                draft.rating == rating ? palette.accent.opacity(0.2) : palette.surface,
                                in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("0 = no idea · 3 = got it with effort · 5 = instant")
                .font(.caption).foregroundStyle(palette.secondaryText)
        }
    }
}

/// A tiny deterministic PRNG, so shuffles are reproducible per exercise.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) | 1
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Wraps subviews onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
