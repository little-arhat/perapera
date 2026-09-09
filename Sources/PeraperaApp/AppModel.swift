import Foundation
import Observation
import SwiftUI
import PeraperaCore

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
        case scratch
        case progress
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
        case progress = "Progress"
        case scratch = "Scratch"
        case archive = "Archive"

        public var id: String { rawValue }

        var icon: String {
            switch self {
            case .practice: "graduationcap"
            case .images: "photo.on.rectangle.angled"
            case .dictionary: "star"
            case .progress: "chart.line.uptrend.xyaxis"
            case .scratch: "text.book.closed"
            case .archive: "tray.full"
            }
        }

        var screen: Screen {
            switch self {
            case .practice: .home
            case .images: .images
            case .dictionary: .lists
            case .progress: .progress
            case .progress: .progress
        case .scratch: .scratch
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
        case .progress: .progress
        case .scratch: .scratch
        case .archive: .archive
        }
    }

    // Settings, persisted in UserDefaults -- per-machine preferences, not
    // learning state. Learning state belongs to Fluent's databases.
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

    /// A focus handed over from another screen, consumed by Practice.
    var pendingFocus: String?
    var savedItems = SavedItems()
    /// Whatever the learner pasted into the scratch pad, kept with the profile.
    var scratchText = "" 
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
    /// Colour は/を/に/で and the rest distinctly.
    ///
    /// Particles are where beginners lose sentences: they are short, unstressed
    /// and carry the whole grammatical structure. Seeing them as a separate
    /// colour turns a wall of kana into a shape.
    var tintParticles: Bool {
        didSet { UserDefaults.standard.set(tintParticles, forKey: "tintParticles") }
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

    /// Nil until a profile is open. A fresh install has no profile, which is a
    /// real state rather than a programmer error, so it has to be representable.
    private(set) var lessonStore: LessonStore?
    private var lessons: LessonService?

    let profiles = ProfileStore()
    private(set) var activeProfile: ProfileStore.Profile?
    let fluentRoot: URL? = Locations.fluentRoot()

    /// Shown once after the one-shot move out of `~/.claude/fluent-data`.
    /// Deliberately not `statusMessage`: that drives the working overlay, which
    /// only the generation and grading paths clear, so a launch-time message
    /// there would pin a spinner on screen for the rest of the session.
    var migrationNotice: String?

    init() {
        AppModel.adoptPreviousDefaults()
        let defaults = UserDefaults.standard
        self.claudePath = defaults.string(forKey: "claudePath")
            ?? Subprocess.which("claude", extraPaths: Locations.toolSearchPaths)
            ?? ""
        self.model = defaults.string(forKey: "model") ?? "opus"
        self.showFurigana = defaults.bool(forKey: "showFurigana")
        let stored = defaults.double(forKey: "textSizeFactor")
        self.textSizeFactor = stored > 0 ? stored : 1.0
        self.textSelectable = defaults.bool(forKey: "textSelectable")
        self.highlightWords = defaults.bool(forKey: "highlightWords")
        self.tintParticles = defaults.bool(forKey: "tintParticles")
        let storedRate = defaults.double(forKey: "speechRate")
        self.speechRate = storedRate > 0 ? storedRate : Double(Speech.Rate.slow)
        self.voiceIdentifier = defaults.string(forKey: "voiceIdentifier") ?? ""
    }

    var dataDirectory: URL? { activeProfile?.directory }

    /// Carries settings across the rename from Fluent to Perapera.
    ///
    /// `UserDefaults.standard` is keyed by bundle identifier, so a new one is an
    /// empty one: the active profile, the `claude` path, text size, speech rate
    /// and the chosen voice would all silently revert. Copied once, and only for
    /// keys the new domain has not already set, so it can never clobber a newer
    /// choice.
    private static func adoptPreviousDefaults() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "adoptedPreviousDefaults"),
              let old = UserDefaults(suiteName: Locations.previousBundleIdentifier)
        else { return }

        let carried = [
            "activeProfileID", "claudePath", "model", "showFurigana",
            "textSizeFactor", "textSelectable", "highlightWords", "tintParticles",
            "speechRate", "voiceIdentifier",
        ]
        for key in carried where defaults.object(forKey: key) == nil {
            if let value = old.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: "adoptedPreviousDefaults")
    }

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
        case .progress:
            return "Progress"
        case .scratch:
            return "Scratch pad"
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
        guard let directory = dataDirectory else {
            lessonStore = nil
            lessons = nil
            store = nil
            return
        }
        let lessonStore = LessonStore(dataDirectory: directory)
        self.lessonStore = lessonStore
        guard let fluentRoot else {
            lessons = nil
            store = nil
            return
        }
        let store = FluentStore(config: .init(fluentRoot: fluentRoot,
                                              dataDirectory: directory))
        self.store = store
        lessons = LessonService(
            claude: ClaudeClient(config: .init(
                executable: claudePath,
                model: model,
                workingDirectory: directory)),
            store: store,
            lessons: lessonStore,
            resources: ResourceLoader(),
            fluentRoot: fluentRoot,
            images: openRouterKey.isEmpty
                ? nil
                : ImagePipeline(config: .init(apiKey: openRouterKey))
        )
    }

    /// One store, shared with `LessonService`. `refresh()` used to build a second
    /// one of its own, which meant two answers to "where are the databases".
    private var store: FluentStore?

    /// Empty when no key is configured, which disables photo exercises rather
    /// than failing a lesson halfway through generating one.
    var openRouterKey: String { Secrets.openRouter() }

    var canGenerateImages: Bool { !openRouterKey.isEmpty }

    func start() async {
        // Off the main actor: this hashes every file of the profile, which is a
        // visible hang once there are a few hundred lesson images.
        let migrator = Migrator(legacy: Locations.legacyDataDirectory,
                                profilesRoot: Locations.profilesRoot,
                                logFile: Locations.migrationLog)
        do {
            let outcome = try await Task.detached { try migrator.run() }.value
            if case let .migrated(_, destination, retired) = outcome {
                profiles.activate(destination.lastPathComponent)
                migrationNotice = "Moved your learning data to \(destination.path). "
                    + "The old copy is at \(retired.path)."
            }
        } catch {
            self.error = error.localizedDescription
        }
        activeProfile = profiles.active
        rebuildServices()
        await refresh()
    }

    /// Switching is a change of subject, not a reload. Everything derived from the
    /// previous learner has to go first, or their name sits in the title bar and a
    /// half-open lesson id resolves to a lesson that is not there.
    func switchProfile(to id: String) async {
        profiles.activate(id)
        activeProfile = profiles.active
        snapshot = nil
        records = []
        savedItems = SavedItems()
        scratchText = ""
        pictures = []
        spending = SpendLog()
        unreadableLessons = []
        error = nil
        screen = .home
        returnTo = nil
        rebuildServices()
        await refresh()
    }

    func refresh() async {
        guard let lessonStore else { return }
        savedItems = (try? lessonStore.loadSavedItems()) ?? SavedItems()
        scratchText = lessonStore.loadScratch()
        pictures = (try? lessonStore.loadPictures()) ?? []
        spending = (try? lessonStore.loadSpending()) ?? SpendLog()
        do {
            let loaded = try lessonStore.loadAll()
            records = loaded.records
            unreadableLessons = loaded.unreadable
        } catch {
            self.error = "Couldn't read the lesson archive: \(error.localizedDescription)"
        }
        guard let store else { return }
        do {
            snapshot = try await store.load()
        } catch {
            self.error = "Couldn't read Fluent's databases: \(error.localizedDescription)"
        }
    }

    // MARK: - Intents

    /// Makes `count` lessons in one go.
    ///
    /// Stocking up before a flight is the whole point of the offline path, and
    /// until now it had to be done one lesson at a time. Each lesson is
    /// generated in turn rather than in parallel: they are written to the same
    /// archive, and each one is told what the previous ones covered so the batch
    /// does not come back as four variations of the same ticket window.
    ///
    /// A failure part-way keeps what was already made. Four lessons minus one is
    /// a worse afternoon than four; nothing at all is a worse one still.
    func generate(
        mode: LessonSpec.Mode, size: LessonSpec.Size,
        depth: LessonSpec.Depth = .standard, focus: String,
        name: String = "", note: String = "", photoExercises: Int = 0,
        count: Int = 1
    ) async {
        guard count > 0 else { return }
        for step in 1...count {
            let made = await generateOne(
                mode: mode, size: size, depth: depth, focus: focus,
                name: name, note: note, photoExercises: photoExercises,
                step: step, of: count)
            guard made else { break }
        }
        if count > 1 {
            statusMessage = nil
            // Staying on Practice: a batch is stock for later, not something to
            // start now, and being dropped into lesson one of four is not what
            // was asked for.
            screen = .home
        }
    }

    /// Returns whether the lesson was made, so a batch stops at the first failure
    /// rather than reporting the same error four times.
    @discardableResult
    private func generateOne(
        mode: LessonSpec.Mode, size: LessonSpec.Size,
        depth: LessonSpec.Depth, focus: String,
        name: String, note: String, photoExercises: Int,
        step: Int, of total: Int
    ) async -> Bool {
        guard let lessons else { return false }
        guard !claudePath.isEmpty else {
            error = "Set the path to `claude` in Settings first."
            return false
        }
        isGenerating = true
        let counted = total > 1 ? " (\(step) of \(total))" : ""
        beginProgress("Building a \(size.rawValue) \(mode.rawValue)\(counted)…")
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
                try? lessonStore?.save(record)
            }
            records.insert(record, at: 0)
            if total == 1 { screen = .lesson(id: record.id) }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
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

    /// Written on leaving the scratch pad rather than on every keystroke: this
    /// is a text file, and a learner pasting a page should not cause a write per
    /// character.
    func persistScratch() {
        try? lessonStore?.saveScratch(scratchText)
    }

    func unsave(id: String) {
        savedItems.remove(id: id)
        persistSavedItems()
    }

    private func persistSavedItems() {
        guard let lessonStore else { return }
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
        guard let lessonStore else { return }
        guard canGenerateImages else {
            error = "No OpenRouter key. Add one in Settings."
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
        guard let lessonStore else { return nil }
        let url = lessonStore.imageURL(lessonId: lessonId, fileName: fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Where a recognition exercise's picture lives on disk.
    func imageURL(for record: LessonRecord, exercise: Exercise) -> URL? {
        guard let lessonStore, let fileName = record.images[exercise.id] else { return nil }
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
        try? lessonStore?.saveSpending(spending)
    }

    nonisolated private func spendSink() -> @Sendable (String, Double, String) -> Void {
        { [weak self] purpose, cost, model in
            Task { @MainActor in self?.noteSpend(purpose, cost, model) }
        }
    }

    func record(id: String) -> LessonRecord? {
        records.first { $0.id == id }
    }

    /// Applies one change to one lesson and persists it.
    ///
    /// The only way a lesson changes. `LessonPlayerView` used to hold its own
    /// `@State` copy and push whole records back, which is two copies of one
    /// identity: whichever wrote last won, and answers leaked between exercises
    /// when the copies drifted.
    func mutate(id: String, _ change: (inout LessonRecord) -> Void) {
        guard var record = record(id: id) else { return }
        change(&record)
        update(record)
    }

    func update(_ record: LessonRecord) {
        guard let lessonStore else { return }
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
        guard let dataDirectory else { return }
        let directory = dataDirectory.appending(path: "lessons")
        for name in unreadableLessons {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
        unreadableLessons = []
    }

    func delete(id: String) {
        guard let lessonStore else { return }
        do {
            try lessonStore.delete(id: id)
            records.removeAll { $0.id == id }
        } catch {
            self.error = "Couldn't delete that lesson: \(error.localizedDescription)"
        }
    }
}
