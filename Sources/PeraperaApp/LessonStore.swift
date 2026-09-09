import Foundation
import PeraperaCore

/// Lessons on disk: one JSON file per lesson, holding its whole life.
///
/// JSON files are authoritative. They sit beside Fluent's own databases, are
/// readable without the app, and survive it. A lesson is a value that accretes
/// answers and then feedback -- never a row that gets overwritten -- so the
/// archive can always show what actually happened.
@MainActor
final class LessonStore {
    private let directory: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(dataDirectory: URL) {
        self.directory = dataDirectory.appending(path: "lessons")
    }

    func prepare() throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    private func url(for id: String) -> URL {
        directory.appending(path: "\(id).json")
    }

    /// Writes via a temp file and an atomic replace, matching what `update-db.py`
    /// does: a crash mid-write must not leave a half-written lesson.
    func save(_ record: LessonRecord) throws {
        try prepare()
        let data = try encoder.encode(record)
        let target = url(for: record.id)
        let temp = target.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(target, withItemAt: temp)
    }

    func load(id: String) throws -> LessonRecord {
        try decoder.decode(LessonRecord.self, from: Data(contentsOf: url(for: id)))
    }

    /// Every lesson, newest first. Unreadable files are reported rather than
    /// skipped silently -- a lesson that vanishes from the archive without
    /// explanation is worse than one that shows up broken.
    func loadAll() throws -> (records: [LessonRecord], unreadable: [String]) {
        try prepare()
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        var records: [LessonRecord] = []
        var unreadable: [String] = []
        for file in files {
            do {
                records.append(try decoder.decode(
                    LessonRecord.self, from: Data(contentsOf: file)))
            } catch {
                unreadable.append(file.lastPathComponent)
            }
        }
        records.sort { $0.lesson.generatedAt > $1.lesson.generatedAt }
        return (records, unreadable)
    }

    // MARK: - Lesson images

    /// Images live beside the lessons, one directory per lesson.
    ///
    /// Separate from the JSON rather than embedded in it: a base64 image would
    /// make the record unreadable in a text editor and undiffable, and the whole
    /// point of a JSON archive is that it outlives the app.
    func assetsDirectory(for lessonId: String) -> URL {
        directory.appending(path: "assets/\(lessonId)")
    }

    func saveImage(_ data: Data, lessonId: String, exerciseId: String) throws -> String {
        let folder = assetsDirectory(for: lessonId)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        let name = "\(exerciseId).jpg"
        try data.write(to: folder.appending(path: name), options: .atomic)
        return name
    }

    func imageURL(lessonId: String, fileName: String) -> URL {
        assetsDirectory(for: lessonId).appending(path: fileName)
    }

    /// Deleting a lesson must take its images too, or the directory grows
    /// without bound with files nothing references.
    func deleteAssets(for lessonId: String) {
        try? FileManager.default.removeItem(at: assetsDirectory(for: lessonId))
    }

    // MARK: - On-demand pictures

    private var picturesURL: URL {
        directory.deletingLastPathComponent().appending(path: "pictures.json")
    }

    func loadPictures() throws -> [StandalonePicture] {
        guard FileManager.default.fileExists(atPath: picturesURL.path) else { return [] }
        return try decoder.decode(
            [StandalonePicture].self, from: Data(contentsOf: picturesURL))
    }

    func savePictures(_ pictures: [StandalonePicture]) throws {
        try prepare()
        let data = try encoder.encode(pictures)
        let temp = picturesURL.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(picturesURL, withItemAt: temp)
    }

    // MARK: - Spending

    private var spendingURL: URL {
        directory.deletingLastPathComponent().appending(path: "spending.json")
    }

    func loadSpending() throws -> SpendLog {
        guard FileManager.default.fileExists(atPath: spendingURL.path) else {
            return SpendLog()
        }
        return try decoder.decode(SpendLog.self, from: Data(contentsOf: spendingURL))
    }

    func saveSpending(_ log: SpendLog) throws {
        try prepare()
        let data = try encoder.encode(log)
        let temp = spendingURL.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(spendingURL, withItemAt: temp)
    }

    // MARK: - Saved items
    //
    // One file beside the lessons, for the same reasons: readable without the
    // app, and outliving it.

    private var savedItemsURL: URL {
        directory.deletingLastPathComponent().appending(path: "saved-items.json")
    }

    func loadSavedItems() throws -> SavedItems {
        guard FileManager.default.fileExists(atPath: savedItemsURL.path) else {
            return SavedItems()
        }
        return try decoder.decode(
            SavedItems.self, from: Data(contentsOf: savedItemsURL))
    }

    func saveSavedItems(_ items: SavedItems) throws {
        try prepare()
        let data = try encoder.encode(items)
        let temp = savedItemsURL.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(savedItemsURL, withItemAt: temp)
    }

    // MARK: - Glosses
    //
    // A word looked up once should not be paid for twice. Kept beside the
    // profile rather than in the dictionary proper: a gloss is a fact about the
    // language, not a decision to study the word.

    private var glossesURL: URL {
        directory.deletingLastPathComponent().appending(path: "glosses.json")
    }

    func loadGlosses() -> [String: Glossary.Entry] {
        guard let data = try? Data(contentsOf: glossesURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Glossary.Entry].self, from: data)) ?? [:]
    }

    func saveGlosses(_ glosses: [String: Glossary.Entry]) throws {
        try prepare()
        let data = try encoder.encode(glosses)
        let temp = glossesURL.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(glossesURL, withItemAt: temp)
    }

    // MARK: - Scratch pad
    //
    // The learner's own text, so it belongs to the profile rather than to this
    // Mac. Plain text rather than JSON: it is prose, and a scratch pad that
    // cannot be opened in any editor is a worse scratch pad.

    private var scratchURL: URL {
        directory.deletingLastPathComponent().appending(path: "scratch.txt")
    }

    func loadScratch() -> String {
        (try? String(contentsOf: scratchURL, encoding: .utf8)) ?? ""
    }

    func saveScratch(_ text: String) throws {
        try prepare()
        try Data(text.utf8).write(to: scratchURL, options: .atomic)
    }

    func delete(id: String) throws {
        deleteAssets(for: id)
        try FileManager.default.removeItem(at: url(for: id))
    }
}
