import SwiftUI
import FluentCore

struct LessonPlayerView: View {
    @Environment(AppModel.self) private var model
    @Environment(Speech.self) private var speech
    @Environment(\.palette) private var palette
    @Environment(\.textScale) private var scale

    @State private var record: LessonRecord
    @State private var index = 0
    @State private var draft = ExerciseDraft()
    /// Set once the learner commits an answer, which is what reveals the verdict.
    @State private var revealed = false
    /// When the learner was last doing something, for active-time accounting.
    @State private var lastInteraction = Date()

    init(record: LessonRecord) {
        _record = State(initialValue: record)
    }

    private var exercise: Exercise { record.lesson.exercises[index] }
    private var isLast: Bool { index == record.lesson.exercises.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if index == 0, let preamble = record.lesson.preamble, !revealed {
                        MarkdownRubyText(markdown: preamble,
                                         showFurigana: model.showFurigana)
                            .padding(16)
                            .background(palette.surface, in: .rect(cornerRadius: 10))
                    }
                    if let passage = exercise.passage, !passage.isEmpty {
                        passageView(passage)
                    }
                    if let spec = exercise.content.imageSpec {
                        RecognitionView(
                            image: spec,
                            fileURL: model.imageURL(for: record, exercise: exercise),
                            revealed: revealed)
                    }
                    prompt
                    if let audioText = exercise.audioText, !audioText.isEmpty {
                        AudioPromptView(
                            text: audioText,
                            language: model.voiceLanguage,
                            isListeningExercise: exercise.skill == .listening)
                    }
                    ExerciseInputView(
                        exercise: exercise, draft: $draft, isLocked: revealed)
                        // Identity per exercise, so SwiftUI discards the input's
                        // internal state when the question changes. Without it
                        // the view is reused, and text typed for one exercise
                        // reappears as -- and is submitted as -- the answer to
                        // the next.
                        .id(exercise.id)
                    if revealed { verdictView }
                }
                .padding(28)
                .frame(maxWidth: scale.width(720), alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            controls
        }
        .onAppear { startIfNeeded() }
    }

    private var progressBar: some View {
        VStack(spacing: 8) {
            HStack {
                Button { model.goBack() } label: {
                    Label("Back to \(model.backDestination)",
                          systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondaryText)
                .keyboardShortcut("[", modifiers: .command)

                Spacer()
                Text("\(index + 1) / \(record.lesson.exercises.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
            }
            ProgressView(value: Double(index), total: Double(record.lesson.exercises.count))
                .tint(palette.accent)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(exercise.skill.rawValue.capitalized)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(palette.surface, in: .capsule)
                if !exercise.isAutoGradable {
                    Label("graded by your teacher", systemImage: "person.fill.checkmark")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer()
                TextSizeControls()
                WordHighlightToggle()
                SelectionToggle()
                if hasKanji {
                    FuriganaToggle(isOn: Binding(
                        get: { model.showFurigana },
                        set: { model.showFurigana = $0 }))
                }
                SaveItemButton(exercise: exercise)
            }
            RubyText(annotated: exercise.prompt, showFurigana: model.showFurigana)
                .foregroundStyle(palette.emphasizedText)
            if let instruction = exercise.instruction {
                Text(instruction)
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText)
                    .selectableIf(scale.selectable)
            }
        }
    }

    private var hasKanji: Bool {
        exercise.displayedText.contains(where: Furigana.hasAnnotations)
    }

    /// Reading-comprehension text. Set apart from the question so the eye can
    /// go back to it, and scrollable so a long passage doesn't push the answer
    /// box off screen.
    private func passageView(_ passage: String) -> some View {
        ScrollView {
            RubyText(annotated: passage, showFurigana: model.showFurigana, size: 19)
                .foregroundStyle(palette.bodyText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
        }
        .frame(maxHeight: 260)
        .background(palette.surface, in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private var verdictView: some View {
        if let verdict = record.verdicts[exercise.id] {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    verdict.isCorrect ? "Correct" : "Not quite",
                    systemImage: verdict.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(verdict.isCorrect ? palette.correct : palette.wrong)

                if !verdict.isCorrect {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Correct version").font(.caption)
                            .foregroundStyle(palette.secondaryText)
                        RubyText(annotated: verdict.correctVersion,
                                 showFurigana: model.showFurigana, size: 20)
                            .foregroundStyle(palette.emphasizedText)
                    }
                }
                if let explanation = exercise.explanation {
                    Text(.init(model.showFurigana
                               ? Furigana.parenthesized(explanation)
                               : Furigana.stripped(explanation)))
                        .foregroundStyle(palette.bodyText)
                        .selectableIf(scale.selectable)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (verdict.isCorrect ? palette.correct : palette.wrong).opacity(0.12),
                in: .rect(cornerRadius: 10))
        } else {
            // Teacher-graded: say so plainly rather than showing a fake verdict.
            VStack(alignment: .leading, spacing: 6) {
                Label("Saved for your teacher", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundStyle(palette.review)
                Text("This one needs judgement, not a lookup. You'll get feedback when you finish the lesson.")
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.review.opacity(0.12), in: .rect(cornerRadius: 10))
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if revealed {
                Button(isLast ? "Finish" : "Next") { advance() }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .keyboardShortcut(.return, modifiers: [])
            } else {
                Button("Skip") { commit(.skipped) }
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Button("Answer") { commit(draft.answer(for: exercise)) }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .disabled(!draft.isAnswerable(for: exercise))
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .controlSize(.large)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: revealed ? .trailing : .leading)
        .background(palette.surface)
    }

    // MARK: - Actions

    private func startIfNeeded() {
        lastInteraction = Date()
        if record.startedAt == nil {
            record.startedAt = Date()
            record.state = .inProgress
            model.update(record)
        }
        // Resume where the learner left off.
        if let next = record.lesson.exercises.firstIndex(where: { record.answers[$0.id] == nil }) {
            index = next
        }
        restoreDraft()
    }

    private func commit(_ answer: Answer) {
        record.recordActivity(since: lastInteraction)
        lastInteraction = Date()
        record.answers[exercise.id] = answer
        if let verdict = Grader.grade(exercise, answer) {
            record.verdicts[exercise.id] = verdict
        }
        model.update(record)
        revealed = true
    }

    private func advance() {
        speech.stop()
        record.recordActivity(since: lastInteraction)
        lastInteraction = Date()
        if isLast {
            record.finishedAt = Date()
            record.state = .completed
            model.update(record)
            model.screen = .debrief(id: record.id)
        } else {
            index += 1
            restoreDraft()
        }
    }

    /// Loads the saved answer for the current exercise back into the draft.
    ///
    /// Revealing an answered exercise renders its verdicts from the draft, so
    /// restoring `revealed` without restoring the answers showed every item as
    /// wrong with an empty field — the answer was still on disk, just not on
    /// screen. Marking work incorrect that the learner got right is the most
    /// damaging thing this app can do, so the two are set together.
    private func restoreDraft() {
        draft = ExerciseDraft(answer: record.answers[exercise.id], for: exercise)
        revealed = record.answers[exercise.id] != nil
    }
}

/// Whatever the learner has typed or picked but not yet committed.
struct ExerciseDraft {
    var text = ""
    var texts: [String] = []
    var choice: Int?
    var order: [Int] = []
    var matches: [Int] = []
    var rating: Int?

    init() {}

    /// Rebuilds a draft from an answer already given, so revisiting an exercise
    /// shows what was actually submitted rather than an empty form.
    init(answer: Answer?, for exercise: Exercise) {
        guard let answer else { return }
        switch answer {
        case let .text(value): text = value
        case let .texts(values): texts = values
        case let .choice(value): choice = value
        case let .order(values): order = values
        case let .matches(values): matches = values
        case let .selfRated(value): rating = value
        case .skipped: break
        }
    }

    func isAnswerable(for exercise: Exercise) -> Bool {
        switch exercise.content {
        case .multipleChoice: choice != nil
        case .cloze, .digitEntry, .translation, .freeResponse, .recognition:
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .reorder(tokens, _): order.count == tokens.count
        case let .matching(pairs): matches.count == pairs.count && !matches.contains(-1)
        case .flashcard: rating != nil
        case let .set(items):
            texts.count == items.count
                && texts.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    func answer(for exercise: Exercise) -> Answer {
        switch exercise.content {
        case .multipleChoice: .choice(choice ?? -1)
        case .cloze, .digitEntry, .translation, .freeResponse, .recognition: .text(text)
        case .reorder: .order(order)
        case .matching: .matches(matches)
        case .flashcard: .selfRated(rating ?? 0)
        case .set: .texts(texts)
        }
    }
}
