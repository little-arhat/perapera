import Foundation

/// A text the learner pasted into the scratch pad and read.
public struct ScratchEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let text: String
    /// When it was last read, not when it was first pasted: the list is "what
    /// I have been working on", and re-reading a text is working on it.
    public var readAt: Date

    public init(id: String = UUID().uuidString, text: String, readAt: Date) {
        self.id = id
        self.text = text
        self.readAt = readAt
    }

    /// The first line, for a list row. A menu's first line names the shop; a
    /// paragraph's first line is as good a handle as any.
    public var summary: String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count <= 60 ? trimmed : String(trimmed.prefix(60)) + "…"
    }

    /// How much there is, for the row's second line.
    public var characterCount: Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }
}

/// What the scratch pad has read, newest first.
///
/// The pad held one text and overwrote it, so a menu read last week was gone
/// the moment the next one was pasted. These are the learner's own materials --
/// the thing a lesson cannot supply -- and they are worth keeping.
public struct ScratchHistory: Codable, Sendable, Equatable {
    public private(set) var entries: [ScratchEntry]

    /// Enough to hold a few weeks of reading. Past this it is a search problem,
    /// and a list nobody scrolls to the end of does not need to be unbounded.
    public static let limit = 50

    public init(entries: [ScratchEntry] = []) {
        self.entries = entries
    }

    /// Records a text as read now.
    ///
    /// Re-reading a text moves it to the top and keeps its identity rather than
    /// adding a second copy: a learner who pastes the same menu twice has one
    /// menu, and a list of duplicates is how a history stops being useful.
    /// Whitespace-only text is not a text.
    public mutating func record(_ text: String, at date: Date) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let index = entries.firstIndex(where: {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
        }) {
            var existing = entries.remove(at: index)
            existing.readAt = date
            entries.insert(existing, at: 0)
        } else {
            entries.insert(ScratchEntry(text: text, readAt: date), at: 0)
        }
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
    }

    public mutating func remove(id: String) {
        entries.removeAll { $0.id == id }
    }

    public func entry(id: String) -> ScratchEntry? {
        entries.first { $0.id == id }
    }
}
