import Foundation

/// Reading kana at speed: see a word, type how it sounds.
///
/// Separate from the script drill, which is about telling one letterform from
/// another. This is about reading a whole word without decoding it character by
/// character, which is the thing that makes a menu readable.
public enum ReadingDrill {
    public enum Script: String, CaseIterable, Codable, Sendable, Identifiable {
        case hiragana, katakana, both

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .hiragana: "Hiragana"
            case .katakana: "Katakana"
            case .both: "Both"
            }
        }

        func accepts(_ word: Word) -> Bool {
            switch self {
            case .hiragana: word.script == "h"
            case .katakana: word.script == "k"
            case .both: true
            }
        }
    }

    public enum Size: String, CaseIterable, Codable, Sendable, Identifiable {
        case small, medium, large

        public var id: String { rawValue }
        public var count: Int {
            switch self {
            case .small: 20
            case .medium: 40
            case .large: 70
            }
        }
        public var label: String { "\(rawValue.capitalized) (\(count))" }
    }

    /// One word as the bundled list holds it.
    public struct Word: Codable, Equatable, Sendable, Identifiable {
        public let w: String
        public let g: String
        public let s: String
        public let t: Int

        public var id: String { w }
        public var text: String { w }
        public var gloss: String { g }
        public var script: String { s }
        /// 1 is the most frequent tier.
        public var tier: Int { t }
    }

    /// What the learner has done with one word.
    ///
    /// SM-2, the same algorithm Fluent uses for everything else, so a word the
    /// learner keeps missing comes back tomorrow and one they know well does
    /// not come back for months.
    public struct Progress: Codable, Equatable, Sendable {
        public var seen: Int = 0
        public var correct: Int = 0
        public var ease: Double = 2.5
        public var interval: Int = 0
        /// Days since the epoch. Zero means never scheduled.
        public var due: Int = 0

        public init() {}
    }

    /// Applies one answer, returning the updated progress.
    ///
    /// Quality is binary here — typed correctly or not — because there is no
    /// partial credit in reading a word. A wrong answer resets the interval to
    /// one day rather than to zero: seeing it again in the same session teaches
    /// recognition of the last few seconds, not of the word.
    public static func record(
        _ progress: Progress, wasCorrect: Bool, today: Int
    ) -> Progress {
        var next = progress
        next.seen += 1
        if wasCorrect {
            next.correct += 1
            next.ease = min(2.8, next.ease + 0.1)
            next.interval = switch next.interval {
            case 0: 1
            case 1: 6
            default: max(1, Int((Double(next.interval) * next.ease).rounded()))
            }
        } else {
            next.ease = max(1.3, next.ease - 0.2)
            next.interval = 1
        }
        next.due = today + next.interval
        return next
    }

    /// Builds a session: everything due first, then new words, most from the
    /// frequent tiers and some rarer.
    ///
    /// Due work comes first because that is what spaced repetition is for; a
    /// session that always shows new words is a vocabulary list, not a review
    /// schedule. When nothing is due the session is all new, which is the right
    /// answer on day one.
    public static func session(
        from words: [Word], script: Script, size: Size,
        progress: [String: Progress], today: Int,
        shuffle: ([Word]) -> [Word] = { $0.shuffled() }
    ) -> [Word] {
        let pool = words.filter(script.accepts)
        guard !pool.isEmpty else { return [] }

        let due = pool.filter { word in
            guard let seen = progress[word.w], seen.seen > 0 else { return false }
            return seen.due <= today
        }
        var chosen = Array(shuffle(due).prefix(size.count))
        guard chosen.count < size.count else { return chosen }

        // Fill with words never seen. Four from the common tiers for every one
        // rarer: enough novelty to keep a session from feeling like a list
        // already learned, not so much that it is mostly words nobody uses.
        let fresh = pool.filter { progress[$0.w]?.seen ?? 0 == 0 }
        let common = shuffle(fresh.filter { $0.tier <= 1 })
        let rarer = shuffle(fresh.filter { $0.tier > 1 })

        var commonIndex = 0, rarerIndex = 0
        while chosen.count < size.count, commonIndex < common.count || rarerIndex < rarer.count {
            let wantRare = chosen.count % 5 == 4
            if wantRare, rarerIndex < rarer.count {
                chosen.append(rarer[rarerIndex]); rarerIndex += 1
            } else if commonIndex < common.count {
                chosen.append(common[commonIndex]); commonIndex += 1
            } else if rarerIndex < rarer.count {
                chosen.append(rarer[rarerIndex]); rarerIndex += 1
            } else {
                break
            }
        }
        return chosen
    }

    /// Days since the epoch, which is all the scheduling needs.
    public static func day(for date: Date = Date()) -> Int {
        Int(date.timeIntervalSince1970 / 86_400)
    }
}
