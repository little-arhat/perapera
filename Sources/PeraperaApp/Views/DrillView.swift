import SwiftUI
import PeraperaCore

/// Translate a batch of saved words, then see how you did.
///
/// A batch rather than one at a time: seeing eight words together is how a
/// textbook drills vocabulary, and it lets the learner skip around and answer
/// the easy ones first — which is both faster and closer to how recall actually
/// behaves.
struct DrillView: View {
    let items: [SavedItem]
    let onFinish: ([String: Bool]) -> Void

    @Environment(\.palette) private var palette
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var direction: WordDrill.Direction = .toNative
    @State private var answers: [String: String] = [:]
    @State private var marked: [String: Verdict?]?

    private var drill: WordDrill {
        WordDrill.build(from: items, direction: direction, limit: 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if drill.questions.isEmpty {
                nothingToDrill
            } else {
                questions
                footer
            }
        }
        .frame(width: 720, height: 620)
    }

    private var header: some View {
        HStack {
            Text("Drill")
                .font(.headline)
                .foregroundStyle(palette.emphasizedText)
            Spacer()
            Picker("", selection: $direction) {
                ForEach(WordDrill.Direction.allCases, id: \.self) {
                    Text($0.label).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .disabled(marked != nil)
            .help("JA → EN tests recognition; EN → JA tests recall, which is harder "
                  + "and the one that matters for speaking.")
        }
        .padding(16)
    }

    private var nothingToDrill: some View {
        VStack(spacing: 8) {
            Text("Nothing to drill yet")
                .font(.headline)
                .foregroundStyle(palette.emphasizedText)
            Text("Saved words need a meaning before they can be translated. "
                 + "Add one from the list, or star a word during a lesson.")
                .font(.callout)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var questions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(drill.questions.enumerated()), id: \.element.id) { index, question in
                    row(index: index, question: question)
                }
            }
            .padding(16)
        }
    }

    private func row(index: Int, question: WordDrill.Question) -> some View {
        let verdict = marked?[question.id] ?? nil
        let wasMarked = marked?.keys.contains(question.id) ?? false

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index + 1).")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 22, alignment: .trailing)

                VStack(alignment: .leading, spacing: 6) {
                    // Furigana follows the same toggle as everywhere else: a
                    // kanji entry is only a test of kanji while the reading is
                    // hidden.
                    RubyText(annotated: question.shown,
                             showFurigana: model.showFurigana, size: 20)

                    HStack(spacing: 8) {
                        field(question)
                            .frame(maxWidth: 300)
                        if wasMarked {
                            Image(systemName: verdict == nil
                                  ? "person.fill.questionmark"
                                  : (verdict!.isCorrect
                                     ? "checkmark.circle.fill" : "xmark.circle.fill"))
                                .foregroundStyle(verdict == nil
                                                 ? palette.review
                                                 : (verdict!.isCorrect
                                                    ? palette.correct : palette.wrong))
                        }
                    }

                    if wasMarked {
                        answerDetail(question, verdict: verdict)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func answerDetail(
        _ question: WordDrill.Question, verdict: Verdict?
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if verdict == nil {
                Text("Close — counted as neither right nor wrong.")
                    .font(.caption)
                    .foregroundStyle(palette.review)
            }
            if verdict?.isCorrect != true {
                Text("→ \(question.accepted.joined(separator: " / "))")
                    .font(.callout)
                    .foregroundStyle(palette.emphasizedText)
            }
            // The sentence is shown only after answering: seeing the word in
            // use beforehand would give the answer away.
            if let example = question.example, !example.isEmpty {
                RubyText(annotated: example, showFurigana: true, size: 15)
                if let gloss = question.exampleGloss, !gloss.isEmpty {
                    Text(gloss)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func field(_ question: WordDrill.Question) -> some View {
        let binding = Binding(
            get: { answers[question.id] ?? "" },
            set: { answers[question.id] = $0 })

        if direction == .toTarget, model.voiceLanguage == "ja-JP" {
            // Answering in Japanese uses the kana field, so the answer is
            // recalled rather than picked from an IME candidate list.
            KanaTextField(text: binding, compact: true)
                .disabled(marked != nil)
        } else {
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
                .disabled(marked != nil)
        }
    }

    private var footer: some View {
        HStack {
            if let marked {
                let right = marked.values.filter { $0?.isCorrect == true }.count
                Text("\(right)/\(marked.count) correct")
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            if marked == nil {
                Button("Check") { check() }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button("Done") { finish() }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .controlSize(.large)
        .padding(16)
        .background(palette.surface)
    }

    private func check() {
        var results: [String: Verdict?] = [:]
        for question in drill.questions {
            results[question.id] = drill.mark(
                question, answer: answers[question.id] ?? "")
        }
        marked = results
    }

    private func finish() {
        // A deferred answer is recorded as neither: counting a close English
        // gloss as a failure would drive the word up the drill list for no
        // reason.
        var outcomes: [String: Bool] = [:]
        for (id, verdict) in marked ?? [:] {
            if let verdict { outcomes[id] = verdict.isCorrect }
        }
        onFinish(outcomes)
        dismiss()
    }
}
