import Foundation
import Observation
import SwiftUI
import FluentCore

/// The app's single piece of mutable state.
///
/// One identity, one succession of values. Views read it and send it intents;
/// nothing else in the app holds mutable state, which is what keeps "what is
/// true right now" answerable in one place.
@MainActor
@Observable
final class AppModel {
    enum Screen: Equatable {
        case home
        case lesson(id: String)
        case archive
        case debrief(id: String)
        case lists
        case images
    }

    /// Top-level areas, as the sidebar lists them.
    ///
    /// Separate from `Screen` on purpose: `Screen` includes places you are sent
    /// (a lesson, a debrief) that are not destinations you pick. Folding the two
    /// together would put "debrief of lesson 7" in the sidebar.
    enum Section: String, CaseIterable, Identifiable {
        case practice = "Practice"
        case images = "Pictures"
        case dictionary = "Saved"
        case archive = "Archive"

        public var id: String { rawValue }

        var icon: String {
            switch self {
            case .practice: "graduationcap"
            case .images: "photo.on.rectangle.angled"
            case .dictionary: "star"
            case .archive: "tray.full"
            }
        }

        var screen: Screen {
            switch self {
            case .practice: .home
            case .images: .images
            case .dictionary: .lists
            case .archive: .archive
            }
        }
    }

    /// Which sidebar row is highlighted for the current screen. A lesson keeps
    /// Practice selected, because that is where it came from.
    var section: Section {
        switch screen {
        case .home, .lesson, .debrief: .practice
        case .images: .images
        case .lists: .dictionary
        case .archive: .archive
        }
    }

    // Settings, persisted in UserDefaults -- per-machine preferences, not
    // learning state. Learning state belongs to Fluent's databases.
    var pluginRoot: URL {
        didSet { UserDefaults.standard.set(pluginRoot.path, forKey: "pluginRoot") }
    }
    var claudePath: String {
        didSet { UserDefaults.standard.set(claudePath, forKey: "claudePath") }
    }
    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "model") }
    }

    /// Readings hidden by default: seeing them every time means never learning
    /// to read the kanji. Persisted, because it is a working preference.
    var showFurigana: Bool {
        didSet { UserDefaults.standard.set(showFurigana, forKey: "showFurigana") }
    }

    var savedItems = SavedItems()
    var pictures: [StandalonePicture] = []
    /// What the app has spent on the learner's behalf.
    var spending = SpendLog()
    var isMakingPicture = false

    /// Target-language text size, persisted. Asked for repeatedly: the default
    /// is too small to read comfortably for a whole session.
    var textSizeFactor: Double {
        didSet { UserDefaults.standard.set(textSizeFactor, forKey: "textSizeFactor") }
    }
    var textSelectable: Bool {
        didSet { UserDefaults.standard.set(textSelectable, forKey: "textSelectable") }
    }
    /// Highlight the word under the pointer, and copy it on click.
    ///
    /// Separate from selection because they answer different questions: "let me
    /// grab this exact span" versus "show me where this word ends". Japanese
    /// has no spaces, so the second is a genuine reading aid rather than a
    /// convenience.
    var highlightWords: Bool {
        didSet { UserDefaults.standard.set(highlightWords, forKey: "highlightWords") }
    }
    /// Slow-playback rate. A stored value rather than a preset because the
    /// scale is badly non-linear — 0.375 and 0.5 are indistinguishable, 0.30 is
    /// obviously slower — so the useful range is narrow and personal.
    var speechRate: Double {
        didSet { UserDefaults.standard.set(speechRate, forKey: "speechRate") }
    }
    /// Chosen voice identifier; empty means "best installed".
    var voiceIdentifier: String {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: "voiceIdentifier") }
    }

    func adjustTextSize(by delta: Double) {
        textSizeFactor = min(TextScale.maximum,
                             max(TextScale.minimum, textSizeFactor + delta))
    }

    func resetTextSize() { textSizeFactor = 1.0 }

    var textScale: TextScale {
        TextScale(factor: textSizeFactor, selectable: textSelectable)
    }

    var screen: Screen = .home
    /// Where a Back button should return to.
    ///
    /// A lesson opened from the Archive belongs back in the Archive, not on the
    /// home screen. The sidebar cannot express that — it selects areas, and a
    /// debrief is not an area — so the origin is remembered when navigating in.
    private(set) var returnTo: Screen?
    var snapshot: FluentStore.Snapshot?
    var records: [LessonRecord] = []
    var unreadableLessons: [String] = []

    var isGenerating = false
    var isSubmitting = false
    var statusMessage: String?
    /// Live detail while the model works: what it is doing, how long it has
    /// taken, and the answer as it is written.
    var progressPhase: String?
    var progressText: String = ""
    var progressStartedAt: Date?
    var error: String?

    private func beginProgress(_ message: String) {
        statusMessage = message
        progressPhase = nil
        progressText = ""
        progressStartedAt = Date()
    }

    private func endProgress() {
        statusMessage = nil
        progressPhase = nil
        progressText = ""
        progressStartedAt = nil
    }

    /// Handed to `ClaudeClient`; called from the subprocess reader thread.
    nonisolated private func progressSink() -> @Sendable (ClaudeClient.Progress) -> Void {
        { [weak self] update in
            Task { @MainActor in
                guard let self else { return }
                self.progressPhase = update.phase.label
                if !update.text.isEmpty { self.progressText = update.text }
            }
        }
    }

    private(set) var lessonStore: LessonStore
    private var lessons: LessonService?

    init() {
        let defaults = UserDefaults.standard
        let root = defaults.string(forKey: "pluginRoot").map(URL.init(fileURLWithPath:))
            ?? Paths.defaultPluginRoot()
        self.pluginRoot = root
        self.claudePath = defaults.string(forKey: "claudePath")
            ?? Subprocess.which("claude", extraPaths: Paths.toolSearchPaths)
            ?? ""
        self.model = defaults.string(forKey: "model") ?? "opus"
        self.showFurigana = defaults.bool(forKey: "showFurigana")
        let stored = defaults.double(forKey: "textSizeFactor")
        self.textSizeFactor = stored > 0 ? stored : 1.0
        self.textSelectable = defaults.bool(forKey: "textSelectable")
        self.highlightWords = defaults.bool(forKey: "highlightWords")
        let storedRate = defaults.double(forKey: "speechRate")
        self.speechRate = storedRate > 0 ? storedRate : Double(Speech.Rate.slow)
        self.voiceIdentifier = defaults.string(forKey: "voiceIdentifier") ?? ""
        self.lessonStore = LessonStore(
            dataDirectory: Paths.dataDirectory(pluginRoot: root))
    }

    var dataDirectory: URL { Paths.dataDirectory(pluginRoot: pluginRoot) }

    /// What the title bar says. Follows the screen, so the window's entry in
    /// Mission Control and the Window menu identifies itself.
    var windowTitle: String {
        switch screen {
        case .home:
            let name = snapshot?.databases.learner_profile.learner.name
            return name.map { "Fluent — \($0)" } ?? "Fluent"
        case let .lesson(id):
            return record(id: id)?.displayTitle ?? "Lesson"
        case let .debrief(id):
            return record(id: id).map { "\($0.displayTitle) — results" } ?? "Results"
        case .archive:
            return "Archive"
        case .lists:
            return "Saved items"
        case .images:
            return "Pictures"
        }
    }

    /// What the learner is part-way through, least finished first.
    ///
    /// Derived from Fluent's spaced-repetition data on every read rather than
    /// cached: mastery is written only by `update-db.py`, and a second copy
    /// here would be a second answer to the same question.
    var topics: [TopicProgress] {
        guard let snapshot else { return [] }
        let today = snapshot.computed.today
        return TopicBreakdown.from(
            items: snapshot.databases.spaced_repetition.items.values.map {
                (
                    category: $0.category ?? "",
                    mastery: $0.mastery_level ?? 0,
                    isDue: ($0.due_date ?? "") <= today
                )
            })
    }

    /// BCP-47 code for speech, derived from the profile rather than configured:
    /// the learner already told Fluent what they are learning.
    var voiceLanguage: String? {
        guard let language = snapshot?.databases.learner_profile.learner.target_language
        else { return nil }
        return Speech.voiceCode(for: language)
    }

    /// Rebuilds the services that depend on settings. Called at launch and
    /// whenever a setting changes, so a corrected path takes effect without a
    /// restart.
    func rebuildServices() {
        lessonStore = LessonStore(dataDirectory: dataDirectory)
        lessons = LessonService(
            claude: ClaudeClient(config: .init(
                executable: claudePath,
                model: model,
                workingDirectory: pluginRoot)),
            store: FluentStore(config: .init(pluginRoot: pluginRoot)),
            lessons: lessonStore,
            resources: ResourceLoader(pluginRoot: pluginRoot),
            images: openRouterKey.isEmpty
                ? nil
                : ImagePipeline(config: .init(apiKey: openRouterKey))
        )
    }

    /// Empty when no key is configured, which disables photo exercises rather
    /// than failing a lesson halfway through generating one.
    var openRouterKey: String { Secrets.openRouter(repoRoot: pluginRoot) }

    var canGenerateImages: Bool { !openRouterKey.isEmpty }

    func start() async {
        rebuildServices()
        await refresh()
    }

    func refresh() async {
        savedItems = (try? lessonStore.loadSavedItems()) ?? SavedItems()
        pictures = (try? lessonStore.loadPictures()) ?? []
        spending = (try? lessonStore.loadSpending()) ?? SpendLog()
        do {
            let loaded = try lessonStore.loadAll()
            records = loaded.records
            unreadableLessons = loaded.unreadable
        } catch {
            self.error = "Couldn't read the lesson archive: \(error.localizedDescription)"
        }
        do {
            snapshot = try await FluentStore(config: .init(pluginRoot: pluginRoot)).load()
        } catch {
            self.error = "Couldn't read Fluent's databases: \(error.localizedDescription)"
        }
    }

    // MARK: - Intents

    func generate(
        mode: LessonSpec.Mode, size: LessonSpec.Size,
        depth: LessonSpec.Depth = .standard, focus: String,
        name: String = "", note: String = "", photoExercises: Int = 0
    ) async {
        guard let lessons else { return }
        guard !claudePath.isEmpty else {
            error = "Set the path to `claude` in Settings first."
            return
        }
        isGenerating = true
        beginProgress("Building a \(size.rawValue) \(mode.rawValue)…")
        defer { isGenerating = false; endProgress() }

        do {
            var record = try await lessons.generate(
                spec: LessonSpec(mode: mode, size: size, depth: depth,
                                 focus: focus, photoExercises: photoExercises),
                recent: Array(records.prefix(6)),
                progress: progressSink(), onSpend: spendSink())
            // The label is the learner's, so it is attached after generation
            // rather than sent to the model.
            record.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilWhenEmpty
            record.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilWhenEmpty
            if record.name != nil || record.note != nil {
                try? lessonStore.save(record)
            }
            records.insert(record, at: 0)
            screen = .lesson(id: record.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Saved items

    func save(content: String, gloss: String, kind: SavedItem.Kind, lessonId: String?) {
        savedItems.add(SavedItem(content: content, gloss: gloss, kind: kind,
                                 sourceLessonId: lessonId))
        persistSavedItems()
    }

    /// Stores how a drill went, so the weakest words come up first next time.
    func recordDrill(_ outcomes: [String: Bool]) {
        for (id, wasCorrect) in outcomes {
            savedItems.record(id: id, wasCorrect: wasCorrect)
        }
        persistSavedItems()
    }

    func unsave(id: String) {
        savedItems.remove(id: id)
        persistSavedItems()
    }

    private func persistSavedItems() {
        do { try lessonStore.saveSavedItems(savedItems) }
        catch { self.error = "Couldn't save your list: \(error.localizedDescription)" }
    }

    /// Generates a lesson built from specific saved items.
    ///
    /// Deliberate practice, so it drills them regardless of due date -- but the
    /// results still feed SM-2, so the schedule stays the single authority on
    /// when they come back on their own.
    func practice(
        items: [SavedItem], size: LessonSpec.Size,
        depth: LessonSpec.Depth = .standard
    ) async {
        guard let lessons, !items.isEmpty else { return }
        isGenerating = true
        beginProgress("Building a lesson from \(items.count) saved item(s)…")
        defer { isGenerating = false; endProgress() }

        do {
            let record = try await lessons.generate(
                spec: LessonSpec(mode: .lesson, size: size, depth: depth,
                                 focus: "these specific saved items"),
                seedItems: items, progress: progressSink(), onSpend: spendSink())
            records.insert(record, at: 0)
            screen = .lesson(id: record.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Opens a lesson where its remaining work actually is.
    ///
    /// A lesson that is finished but ungraded must not reopen at question one —
    /// the learner would have to click through every exercise again to reach
    /// the Finish button.
    func open(_ record: LessonRecord) {
        returnTo = screen
        screen = record.state == .generated || record.state == .inProgress
            ? .lesson(id: record.id)
            : .debrief(id: record.id)
    }

    /// Goes back to wherever the current lesson or debrief was opened from,
    /// falling back to Practice.
    /// Navigates to a sidebar area, clearing any remembered origin — picking a
    /// row is a fresh start, not a step in a trail.
    func show(_ section: Section) {
        returnTo = nil
        screen = section.screen
    }

    func goBack() {
        screen = returnTo ?? .home
        returnTo = nil
    }

    /// What the Back button should say, so it names the destination rather than
    /// making the learner guess.
    var backDestination: String {
        switch returnTo {
        case .archive: "Archive"
        case .lists: "Saved"
        case .images: "Pictures"
        default: "Practice"
        }
    }

    /// Renames or annotates a lesson after the fact. Queuing lessons ahead of
    /// time is only useful if you can still tell them apart a week later.
    func label(id: String, name: String, note: String) {
        guard var record = record(id: id) else { return }
        record.name = name.trimmingCharacters(in: .whitespacesAndNewlines).nilWhenEmpty
        record.note = note.trimmingCharacters(in: .whitespacesAndNewlines).nilWhenEmpty
        update(record)
    }

    /// Every photograph collected so far, newest first — from lessons and made
    /// on demand alike.
    var imageLibrary: [LibraryImage] {
        ImageLibrary.collect(from: records, standalone: pictures)
    }

    /// Makes one picture now, outside any lesson.
    ///
    /// The scene is composed locally from a surface template, so this costs one
    /// image call and nothing for a model to write the description.
    func makePicture(_ request: PictureRequest) async {
        guard canGenerateImages else {
            error = "No OpenRouter key. Add OPENROUTER_FLUENT to .env in the Fluent repo."
            return
        }
        isMakingPicture = true
        beginProgress("Making a picture of \(request.sourceLabel)…")
        defer { isMakingPicture = false; endProgress() }

        let pipeline = ImagePipeline(config: .init(apiKey: openRouterKey))
        let language = snapshot?.databases.learner_profile.learner.target_language
            ?? "Japanese"
        let spec = Exercise.ImageSpec(
            scene: request.surface.scene(language: language),
            targets: request.targets,
            question: "What does it say?")

        do {
            let built = try await pipeline.build(
                for: Exercise.placeholder(id: UUID().uuidString), spec: spec
            ) { [weak self] note in
                self?.progressPhase = note
            }
            noteSpend("Picture", built.costUSD, pipeline.config.generationModel)
            let picture = StandalonePicture(
                fileName: "",
                targets: request.targets, accepted: request.accepted,
                question: spec.question, sourceLabel: request.sourceLabel)
            let fileName = try lessonStore.saveImage(
                built.jpeg, lessonId: ImageLibrary.standaloneFolder,
                exerciseId: picture.id)
            pictures.insert(
                StandalonePicture(
                    id: picture.id, fileName: fileName, targets: picture.targets,
                    accepted: picture.accepted, question: picture.question,
                    sourceLabel: picture.sourceLabel, createdAt: picture.createdAt),
                at: 0)
            try lessonStore.savePictures(pictures)
        } catch {
            // The pipeline throws when the writing came out wrong, which is the
            // point — a picture spelling the word incorrectly is worse than none.
            self.error = error.localizedDescription
        }
    }

    func imageURL(lessonId: String, fileName: String) -> URL? {
        let url = lessonStore.imageURL(lessonId: lessonId, fileName: fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Where a recognition exercise's picture lives on disk.
    func imageURL(for record: LessonRecord, exercise: Exercise) -> URL? {
        guard let fileName = record.images[exercise.id] else { return nil }
        return lessonStore.imageURL(lessonId: record.id, fileName: fileName)
    }

    /// Takes the vocabulary the teacher proposed into the dictionary.
    ///
    /// The teacher already returns `newVocabulary` for Fluent's scheduler; the
    /// same words are what the learner would want to drill, and asking them to
    /// re-type words the teacher just named would be absurd. Existing entries
    /// are enriched rather than replaced — the learner's own note outranks a
    /// generated one.
    private func absorbTeacherVocabulary(from feedback: Feedback?) {
        guard let proposed = feedback?.newVocabulary else { return }
        for entry in proposed {
            let kind: SavedItem.Kind = switch entry.itemType {
            case "grammar_rule": .grammar
            default: Furigana.stripped(entry.content).count == 1 ? .kanji : .word
            }
            let item = SavedItem(
                content: entry.content, gloss: entry.answer, kind: kind,
                sourceLessonId: nil,
                reading: entry.reading, example: entry.example,
                exampleGloss: entry.exampleGloss)
            savedItems.add(item)
            savedItems.enrich(
                id: item.id, gloss: entry.answer, reading: entry.reading,
                example: entry.example, exampleGloss: entry.exampleGloss)
        }
    }

    /// Records one paid call and shows it. Every call the app makes on the
    /// learner's behalf lands here — a cost only met on a bill is one nobody
    /// can act on.
    func noteSpend(_ purpose: String, _ cost: Double, _ model: String) {
        guard cost > 0 else { return }
        spending.record(Spend(purpose: purpose, model: model, costUSD: cost))
        try? lessonStore.saveSpending(spending)
    }

    nonisolated private func spendSink() -> @Sendable (String, Double, String) -> Void {
        { [weak self] purpose, cost, model in
            Task { @MainActor in self?.noteSpend(purpose, cost, model) }
        }
    }

    func record(id: String) -> LessonRecord? {
        records.first { $0.id == id }
    }

    func update(_ record: LessonRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        }
        do { try lessonStore.save(record) }
        catch { self.error = "Couldn't save your answers: \(error.localizedDescription)" }
    }

    func submit(id: String) async {
        guard let lessons, var record = record(id: id) else { return }
        isSubmitting = true
        beginProgress(record.feedback == nil
                      ? "Your teacher is reading your answers…"
                      : "Saving to Fluent…")
        defer { isSubmitting = false; endProgress() }

        do {
            record = try await lessons.submit(record, saved: savedItems.pending,
                                              progress: progressSink(),
                                              onSpend: spendSink())
            // Saved items ride along with the session report, so they enter
            // spaced repetition through Fluent rather than a parallel schedule.
            savedItems.markPromoted(ids: Set(savedItems.pending.map(\.id)))
            absorbTeacherVocabulary(from: record.feedback)
            persistSavedItems()
            update(record)
            screen = .debrief(id: record.id)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Removes files the archive could not parse. Explicit and learner-driven:
    /// the app never quietly deletes something it failed to understand.
    func deleteUnreadableLessons() {
        let directory = dataDirectory.appending(path: "lessons")
        for name in unreadableLessons {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
        unreadableLessons = []
    }

    func delete(id: String) {
        do {
            try lessonStore.delete(id: id)
            records.removeAll { $0.id == id }
        } catch {
            self.error = "Couldn't delete that lesson: \(error.localizedDescription)"
        }
    }
}
