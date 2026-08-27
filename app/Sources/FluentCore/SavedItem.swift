import Foundation

/// A word, kanji, or phrase the learner marked for practice.
///
/// This is a *queue*, not a second system of record. An item sits here only
/// until the lesson it came from is submitted; at that point it goes into
/// Fluent's spaced-repetition database through the same `new_vocabulary` path
/// everything else uses, and SM-2 schedules it like any other item. Keeping a
/// parallel store of "my words" with its own scheduling would be two answers to
/// one question.
public struct SavedItem: Codable, Sendable, Identifiable, Equatable {
    /// Stable id, used both here and as the spaced-repetition item id, so
    /// starring the same word twice can never create two schedules for it.
    public let id: String
    /// The target-language text, furigana annotations included.
    public let content: String
    /// Meaning or reading, in the learner's language.
    public var gloss: String
    public var kind: Kind
    public let savedAt: Date
    /// Which lesson it was starred in, so the archive can explain itself.
    public let sourceLessonId: String?
    /// Set once it has been handed to Fluent; a submitted item stays visible in
    /// the list but is no longer pending.
    public var promotedAt: Date?

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case word, kanji, phrase, grammar

        public var label: String {
            switch self {
            case .word: "Word"
            case .kanji: "Kanji"
            case .phrase: "Phrase"
            case .grammar: "Grammar"
            }
        }

        /// How Fluent's spaced-repetition database types it.
        public var fluentItemType: String {
            switch self {
            case .grammar: "grammar_rule"
            default: "vocabulary"
            }
        }
    }

    public var isPending: Bool { promotedAt == nil }

    public init(
        content: String, gloss: String, kind: Kind,
        sourceLessonId: String?, savedAt: Date = Date()
    ) {
        self.id = SavedItem.identifier(for: content)
        self.content = content
        self.gloss = gloss
        self.kind = kind
        self.savedAt = savedAt
        self.sourceLessonId = sourceLessonId
        self.promotedAt = nil
    }

    /// Derived from the content itself, so the same word always maps to the same
    /// id no matter which lesson it was starred in.
    public static func identifier(for content: String) -> String {
        let stripped = Furigana.stripped(content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Non-latin scripts don't slugify, so hash them into something stable
        // and filename-safe while staying readable for latin text.
        let latin = stripped.lowercased().replacingOccurrences(
            of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if !latin.isEmpty, latin.count >= 3 {
            return "saved_\(latin)"
        }
        var hash: UInt64 = 5381
        for scalar in stripped.unicodeScalars {
            hash = hash &* 33 &+ UInt64(scalar.value)
        }
        return "saved_\(String(hash, radix: 36))"
    }
}

/// The learner's saved items, as a value.
public struct SavedItems: Codable, Sendable {
    public var items: [SavedItem]

    public init(items: [SavedItem] = []) {
        self.items = items
    }

    public var pending: [SavedItem] { items.filter(\.isPending) }

    public func contains(_ content: String) -> Bool {
        let id = SavedItem.identifier(for: content)
        return items.contains { $0.id == id }
    }

    /// Adds an item, or returns unchanged if it is already saved. Starring twice
    /// is a no-op rather than a duplicate.
    public mutating func add(_ item: SavedItem) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
    }

    public mutating func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    /// Marks items as handed to Fluent.
    public mutating func markPromoted(ids: Set<String>, at date: Date = Date()) {
        for index in items.indices where ids.contains(items[index].id) {
            items[index].promotedAt = date
        }
    }
}
