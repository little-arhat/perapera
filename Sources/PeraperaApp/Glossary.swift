import Foundation
import PeraperaCore

/// What a word means, from the cheapest source that knows.
///
/// The learner's own dictionary first, then whatever Dictionary.app has enabled,
/// then a small model call. Each answer is cached in the profile, so a word is
/// paid for once and then belongs to the learner offline.
@MainActor
final class Glossary {
    struct Entry: Codable, Equatable, Sendable {
        let word: String
        let reading: String?
        let meaning: String
        /// Where it came from, so the learner can weigh it.
        let source: String
    }

    private let store: LessonStore
    private let claude: ClaudeClient?
    /// Answers already paid for. A word is looked up once, ever.
    private var cache: [String: Entry]

    init(store: LessonStore, claude: ClaudeClient?) {
        self.store = store
        self.claude = claude
        self.cache = store.loadGlosses()
    }

    /// An answer that costs nothing, or nil.
    func known(_ word: String, savedItems: SavedItems) -> Entry? {
        if let saved = savedItems.items.first(where: {
            $0.id == SavedItem.identifier(for: word)
        }), !saved.gloss.isEmpty {
            return Entry(word: word, reading: saved.reading,
                         meaning: saved.gloss, source: "your dictionary")
        }
        if let cached = cache[word] { return cached }
        if let system = SystemDictionary.define(word) {
            return Entry(word: word, reading: JapaneseReadings.reading(of: word),
                         meaning: system, source: "macOS dictionary")
        }
        return nil
    }

    /// Asks the model, once, and remembers the answer.
    ///
    /// Schema-validated like every other call, and deliberately tiny: one word
    /// in, a reading and a short meaning out. Anything longer is a lesson, not a
    /// gloss.
    func lookUp(
        _ word: String, onSpend: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> Entry {
        guard let claude else { throw Failure.noClaude }
        struct Reply: Decodable {
            let reading: String
            let meaning: String
        }
        let schema = """
            {"type":"object","properties":{"reading":{"type":"string"},\
            "meaning":{"type":"string"}},"required":["reading","meaning"],\
            "additionalProperties":false}
            """
        let reply = try await claude.request(
            Reply.self,
            prompt: "Japanese word: \(word)\n\nGive its kana reading and a short "
                + "English meaning, at most eight words. No notes, no examples.",
            systemPrompt: "You are a Japanese-English dictionary. You answer with "
                + "one JSON object matching the schema and nothing else.",
            schema: schema, onSpend: onSpend)
        let entry = Entry(word: word, reading: reply.reading,
                          meaning: reply.meaning, source: "looked up")
        cache[word] = entry
        try? store.saveGlosses(cache)
        return entry
    }

    enum Failure: LocalizedError {
        case noClaude
        var errorDescription: String? {
            "Set the path to `claude` in Settings to look words up."
        }
    }
}

/// The definition Dictionary.app would show, if the learner has a Japanese
/// dictionary enabled.
///
/// Free, offline and instant when it answers. It returns nothing when no
/// Japanese dictionary is turned on, which is the default, so it is a shortcut
/// rather than the mechanism.
enum SystemDictionary {
    static func define(_ word: String) -> String? {
        guard let raw = DCSCopyTextDefinition(nil, word as CFString,
                                              CFRangeMake(0, word.utf16.count))?
            .takeRetainedValue() as String?
        else { return nil }
        // The definition arrives as one long line with the headword first.
        // A popover wants a sentence, not a dictionary page.
        let trimmed = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(200))
    }
}

@_silgen_name("DCSCopyTextDefinition")
private func DCSCopyTextDefinition(
    _ dictionary: AnyObject?, _ string: CFString, _ range: CFRange
) -> Unmanaged<CFString>?
