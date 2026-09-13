import SwiftUI
import PeraperaCore

/// See a word, type how it sounds.
///
/// The script drill is about telling シ from ツ. This is the next thing up:
/// reading a whole word without decoding it letter by letter, which is what
/// makes a menu readable rather than solvable.
///
/// Free and offline. The words are a bundled slice of JMdict and the schedule is
/// SM-2, the same algorithm Fluent uses for everything else, so a word keeps
/// coming back until it is genuinely known.
struct ReadingPracticeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(Speech.self) private var speech

    @State private var script: ReadingDrill.Script = .hiragana
    @State private var size: ReadingDrill.Size = .small
    @State private var queue: [ReadingDrill.Word] = []
    @State private var index = 0
    @State private var typed = ""
    @State private var verdict: Bool?
    @State private var right = 0
    @FocusState private var typing: Bool

    private var current: ReadingDrill.Word? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if queue.isEmpty {
                    setup
                } else if let current {
                    card(current)
                } else {
                    finished
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Reading practice").font(.title2)
                    .foregroundStyle(palette.emphasizedText)
                Spacer()
                if !queue.isEmpty {
                    Text("\(min(index + 1, queue.count)) / \(queue.count) · \(right) right")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            Text("Read the word and type how it sounds. Costs nothing and works offline.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
        }
    }

    // MARK: - Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Script", selection: $script) {
                ForEach(ReadingDrill.Script.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Length", selection: $size) {
                ForEach(ReadingDrill.Size.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(dueSummary)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)

            Button("Start") { start() }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.kanaWords.isEmpty)

            if model.kanaWords.isEmpty {
                Text("The word list is missing from this build.")
                    .font(.caption).foregroundStyle(palette.wrong)
            }
        }
        .padding(20)
        .background(palette.surface, in: .rect(cornerRadius: 12))
    }

    /// What the schedule has waiting, so starting is an informed choice rather
    /// than a surprise.
    private var dueSummary: String {
        let today = ReadingDrill.day()
        let due = model.kanaWords.filter { word in
            guard let seen = model.readingProgress[word.text], seen.seen > 0 else { return false }
            return seen.due <= today
        }.count
        let known = model.readingProgress.values.filter { $0.seen > 0 }.count
        if known == 0 { return "\(model.kanaWords.count) words available. Nothing scheduled yet." }
        return "\(due) due for review, \(known) words seen so far."
    }

    // MARK: - One word

    private func card(_ word: ReadingDrill.Word) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Text(word.text)
                    .font(.system(size: 76, weight: .medium))
                    .foregroundStyle(palette.emphasizedText)
                    .textSelection(.disabled)
                Spacer()
            }

            TextField("How does it sound?", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 22, design: .monospaced))
                .focused($typing)
                .disabled(verdict != nil)
                .onSubmit { verdict == nil ? check(word) : advance() }

            if let verdict {
                VStack(alignment: .leading, spacing: 6) {
                    Label(verdict ? "Right" : "Not quite",
                          systemImage: verdict ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(verdict ? palette.correct : palette.wrong)
                    Text("\(word.text) — \(KanaRomaji.romaji(word.text)) — \(word.gloss)")
                        .font(.callout)
                        .foregroundStyle(palette.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button("Next") { advance() }
                            .buttonStyle(.borderedProminent)
                            .tint(palette.accent)
                            .keyboardShortcut(.defaultAction)
                        Button {
                            speech.speak(word.text, language: model.voiceLanguage,
                                         rate: Float(model.speechRate),
                                         voiceIdentifier: model.voiceIdentifier.isEmpty
                                             ? nil : model.voiceIdentifier)
                        } label: {
                            Label("Hear it", systemImage: "speaker.wave.2")
                        }
                        Button("Save to my list") {
                            model.save(content: word.text, gloss: word.gloss,
                                       kind: .word, lessonId: nil)
                        }
                    }
                }
                .padding(14)
                .background(palette.surface, in: .rect(cornerRadius: 10))
            } else {
                Button("Check") { check(word) }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .background(palette.surface.opacity(0.6), in: .rect(cornerRadius: 12))
        .onAppear { typing = true }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Done — \(right) of \(queue.count)")
                .font(.title3)
                .foregroundStyle(palette.emphasizedText)
            Text("Words you missed are scheduled for tomorrow; the rest move further out.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
            Button("Again") { queue = []; index = 0; right = 0 }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .background(palette.surface, in: .rect(cornerRadius: 12))
    }

    // MARK: - Actions

    private func start() {
        queue = ReadingDrill.session(
            from: model.kanaWords, script: script, size: size,
            progress: model.readingProgress, today: ReadingDrill.day())
        index = 0
        right = 0
        typed = ""
        verdict = nil
    }

    private func check(_ word: ReadingDrill.Word) {
        let correct = KanaRomaji.accepts(typed, for: word.text)
        verdict = correct
        if correct { right += 1 }
        model.recordReading(word.text, wasCorrect: correct)
    }

    private func advance() {
        typed = ""
        verdict = nil
        index += 1
        typing = true
    }
}
