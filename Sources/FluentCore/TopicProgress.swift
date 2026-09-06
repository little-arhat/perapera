import Foundation

/// How far through a topic the learner is.
///
/// Fluent has tracked this all along — every spaced-repetition item carries a
/// category and a mastery level — but the app never read it, so every lesson
/// landed on the same material with no sense of whether that material was
/// nearly done or barely begun.
///
/// Derived, never stored: mastery lives in Fluent's databases and is written
/// only by `update-db.py`. Keeping a second copy here would be a second answer
/// to the same question.
public struct TopicProgress: Equatable, Sendable, Identifiable {
    public let name: String
    /// Items never answered correctly yet (mastery 0).
    public let new: Int
    /// Seen, not yet reliable (1-2).
    public let learning: Int
    /// Reliable, still scheduled (3-4).
    public let strong: Int
    /// Mastered (5).
    public let mastered: Int
    /// Due for review right now.
    public let due: Int

    public var id: String { name }
    public var total: Int { new + learning + strong + mastered }

    /// 0.0-1.0, weighting partial progress rather than counting only mastery.
    ///
    /// All-or-nothing would show 0% for a topic the learner half knows, which
    /// is both discouraging and wrong — the point of the number is to say which
    /// topic is least finished, and a topic of eight half-learned items is
    /// further along than one of eight untouched ones.
    public var completion: Double {
        guard total > 0 else { return 0 }
        let earned = Double(learning) * 0.4 + Double(strong) * 0.8 + Double(mastered)
        return earned / Double(total)
    }

    /// A short human verdict, so the number is not the only signal.
    public var verdict: String {
        switch completion {
        case ..<0.15: "barely started"
        case ..<0.45: "in progress"
        case ..<0.75: "getting there"
        case ..<0.95: "nearly done"
        default: "done"
        }
    }

    public init(
        name: String, new: Int, learning: Int, strong: Int, mastered: Int, due: Int
    ) {
        self.name = name
        self.new = new
        self.learning = learning
        self.strong = strong
        self.mastered = mastered
        self.due = due
    }
}

public enum TopicBreakdown {
    /// One entry per category, least complete first.
    ///
    /// Least complete first because the list exists to answer "what should I
    /// work on?", and the honest answer is rarely the topic already at 80%.
    /// Ties break on size, so a large unfinished topic outranks a small one.
    public static func from(
        items: [(category: String, mastery: Int, isDue: Bool)],
        minimumItems: Int = 2
    ) -> [TopicProgress] {
        var buckets: [String: (Int, Int, Int, Int, Int)] = [:]
        for item in items {
            let key = display(item.category)
            guard !key.isEmpty else { continue }
            var bucket = buckets[key] ?? (0, 0, 0, 0, 0)
            switch item.mastery {
            case ..<1: bucket.0 += 1
            case 1...2: bucket.1 += 1
            case 3...4: bucket.2 += 1
            default: bucket.3 += 1
            }
            if item.isDue { bucket.4 += 1 }
            buckets[key] = bucket
        }

        return buckets
            .map {
                TopicProgress(name: $0.key, new: $0.value.0, learning: $0.value.1,
                              strong: $0.value.2, mastered: $0.value.3,
                              due: $0.value.4)
            }
            // A one-item "topic" is a stray tag, not a subject worth a row.
            .filter { $0.total >= minimumItems }
            .sorted {
                $0.completion == $1.completion
                    ? $0.total > $1.total
                    : $0.completion < $1.completion
            }
    }

    /// Turns a stored category key into something readable.
    ///
    /// Generators emit both `travel_station` and `grammar_requests`; the shared
    /// prefixes are how the data was filed, not what the learner is studying.
    static func display(_ category: String) -> String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "saved ", with: "")
    }
}
