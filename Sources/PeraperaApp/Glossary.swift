import Foundation
import PeraperaCore

/// What a word means, from whatever already knows.
///
/// No model call. Asking one cost a fraction of a cent and several seconds, and
/// a lookup you wait for is a lookup you stop using -- which for a reading aid
/// is the same as it not working. A bundled dictionary answers instantly for the
/// words a learner actually clicks, and JapanDict is one button away for the
/// rest, with more than a one-line gloss when you get there.
@MainActor
struct Glossary {
    struct Entry: Equatable, Sendable {
        let word: String
        let reading: String?
        let meaning: String
        /// Where it came from, so the learner can weigh it.
        let source: String
    }

    /// The learner's own dictionary first: a note they wrote outranks a gloss.
    func known(_ word: String, savedItems: SavedItems) -> Entry? {
        let bare = Furigana.stripped(word)
        if let saved = savedItems.items.first(where: {
            $0.id == SavedItem.identifier(for: word)
        }), !saved.gloss.isEmpty {
            return Entry(word: word, reading: saved.reading,
                         meaning: saved.gloss, source: "your dictionary")
        }
        if let entry = Bundled.shared.look(up: word) {
            return Entry(word: word,
                         reading: entry.reading ?? JapaneseReadings.reading(of: bare),
                         meaning: entry.gloss, source: "dictionary")
        }
        if let system = SystemDictionary.define(bare) {
            return Entry(word: word, reading: JapaneseReadings.reading(of: bare),
                         meaning: system, source: "macOS dictionary")
        }
        return nil
    }
}

/// The bundled slice of JMdict, loaded the first time something is looked up.
///
/// Four megabytes of JSON, so it is not decoded at launch: nothing needs it
/// until a word is clicked, and paying that on every start for a feature that
/// might not be used is the wrong trade.
///
/// Main-actor confined rather than locked: every caller is a view or the model,
/// which are already there, and a lock would be machinery for contention that
/// cannot happen.
@MainActor
final class Bundled {
    struct Entry: Decodable {
        let r: String?
        let g: String
        var reading: String? { r }
        var gloss: String { g }
    }

    static let shared = Bundled()
    private var index: [String: Entry]?

    func look(up word: String) -> Entry? {
        if index == nil {
            guard let url = Bundle.module.url(forResource: "lookup", withExtension: "json",
                                              subdirectory: "Words"),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
            else {
                index = [:]
                return nil
            }
            index = decoded
        }
        // A clicked word may carry furigana markup from the lesson it came from.
        return index?[Furigana.stripped(word)]
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
        let trimmed = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(200))
    }
}

@_silgen_name("DCSCopyTextDefinition")
private func DCSCopyTextDefinition(
    _ dictionary: AnyObject?, _ string: CFString, _ range: CFRange
) -> Unmanaged<CFString>?
