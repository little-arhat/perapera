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
    @State private var mode: ReadingDrill.Mode = .review
    @State private var queue: [ReadingDrill.Word] = []
    @State private var index = 0
    @State private var typed = ""
    @State private var verdict: Bool?
    /// Whether the answer is on screen. A wrong attempt does not put it there:
    /// being shown the answer the instant you slip removes the second or two in
    /// which you would have worked it out, which is where the learning is.
    @State private var revealed = false
    /// What the first attempt was, or nil before one. The schedule records the
    /// first attempt only, so trying again costs nothing and changes nothing.
    @State private var graded: Bool?
    @State private var right = 0
    /// What has been answered, newest first. A correct answer moves straight on,
    /// so this is where the word you just read goes -- the pace is the point, and
    /// a confirmation you have to dismiss is the thing that breaks it.
    @State private var history: [Answered] = []
    @FocusState private var typing: Bool

    struct Answered: Identifiable {
        let id = UUID()
        let word: ReadingDrill.Word
        let firstTry: Bool
    }

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
                    recent
                } else {
                    finished
                    recent
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

            Picker("Mode", selection: $mode) {
                ForEach(ReadingDrill.Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(mode.summary)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)

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
        if mode == .shuffle {
            let pool = ReadingDrill.mostFrequent(model.kanaWords, script: script)
            return "\(pool.count) of the most frequent \(script.label.lowercased()) words."
        }
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
                .disabled(revealed)
                .onSubmit { revealed ? advance(word) : check(word) }

            if revealed {
                answerBlock(word)
            } else {
                if verdict == false {
                    Text("Not quite. Try again, or show the answer.")
                        .font(.callout)
                        .foregroundStyle(palette.wrong)
                }
                HStack(spacing: 10) {
                    Button("Check") { check(word) }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                        .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                    if verdict == false {
                        Button("Show answer") { revealed = true }
                        Button("Skip") { advance(word) }
                    }
                }
            }
        }
        .padding(20)
        .background(palette.surface.opacity(0.6), in: .rect(cornerRadius: 12))
        .onAppear { typing = true }
    }

    private func answerBlock(_ word: ReadingDrill.Word) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Only reached by asking to be shown, which means the first attempt
            // was wrong. A correct answer never stops here -- it moves on and
            // lands in the strip below.
            Label("The answer", systemImage: "lightbulb")
                .foregroundStyle(palette.secondaryText)
            Text("\(word.text) — \(KanaRomaji.romaji(word.text)) — \(word.gloss)")
                .font(.callout)
                .foregroundStyle(palette.bodyText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Next") { advance(word) }
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
    }

    /// What you just read, smaller and out of the way.
    ///
    /// A correct answer no longer stops to show a panel, so this is where the
    /// reading and the meaning go. Three rows: enough to glance back at the one
    /// you half-guessed, not so many that it competes with the word in front.
    @ViewBuilder
    private var recent: some View {
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(history.prefix(3)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: entry.firstTry
                              ? "checkmark.circle.fill" : "circle.dotted")
                            .font(.caption2)
                            .foregroundStyle(entry.firstTry
                                             ? palette.correct : palette.secondaryText)
                        Text(entry.word.text)
                            .font(.system(size: 17))
                            .foregroundStyle(palette.bodyText)
                        Text(KanaRomaji.romaji(entry.word.text))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                        Text(entry.word.gloss)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                        Spacer()
                        if entry.id == history.first?.id {
                            Button {
                                speech.speak(entry.word.text, language: model.voiceLanguage,
                                             rate: Float(model.speechRate),
                                             voiceIdentifier: model.voiceIdentifier.isEmpty
                                                 ? nil : model.voiceIdentifier)
                            } label: { Image(systemName: "speaker.wave.2") }
                                .buttonStyle(.plain)
                                .help("Hear it")
                            Button {
                                model.save(content: entry.word.text, gloss: entry.word.gloss,
                                           kind: .word, lessonId: nil)
                            } label: { Image(systemName: "star") }
                                .buttonStyle(.plain)
                                .help("Save to my list")
                        }
                    }
                    .opacity(entry.id == history.first?.id ? 1 : 0.55)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface.opacity(0.5), in: .rect(cornerRadius: 10))
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Done — \(right) of \(queue.count)")
                .font(.title3)
                .foregroundStyle(palette.emphasizedText)
            Text("Words you missed are scheduled for tomorrow; the rest move further out.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
            Button("Again") { queue = []; index = 0; right = 0; history = [] }
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
            from: model.kanaWords, script: script, size: size, mode: mode,
            progress: model.readingProgress, today: ReadingDrill.day())
        index = 0
        right = 0
        typed = ""
        verdict = nil
        revealed = false
        graded = nil
        history = []
    }

    private func check(_ word: ReadingDrill.Word) {
        let correct = KanaRomaji.accepts(typed, for: word.text)
        verdict = correct
        // Graded once, on the first attempt. The schedule is a record of whether
        // the word was known, not of whether it was eventually arrived at, and a
        // second try that succeeds should not move it months out.
        if graded == nil {
            graded = correct
            if correct { right += 1 }
            model.recordReading(word.text, wasCorrect: correct)
        }
        // Right means on to the next one. The word lands in the strip below with
        // its reading, so nothing is lost by not stopping to read a panel.
        if correct { advance(word) }
    }

    private func advance(_ word: ReadingDrill.Word) {
        history.insert(Answered(word: word, firstTry: graded == true), at: 0)
        moveOn()
    }

    private func moveOn() {
        typed = ""
        verdict = nil
        revealed = false
        graded = nil
        index += 1
        typing = true
    }
}
