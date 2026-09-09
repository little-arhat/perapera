import Foundation

/// What one call to a model cost, and what it was for.
///
/// Recorded because this app spends the learner's money on their behalf, in
/// amounts small enough to be invisible one at a time and material over a
/// month. A number you only meet on a bill is a number you cannot act on.
public struct Spend: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    /// Plain words: "Lesson", "Grading", "Picture", "Checking a picture".
    public let purpose: String
    public let model: String
    public let costUSD: Double
    public let at: Date

    public init(
        id: String = UUID().uuidString,
        purpose: String, model: String, costUSD: Double, at: Date = Date()
    ) {
        self.id = id
        self.purpose = purpose
        self.model = model
        self.costUSD = costUSD
        self.at = at
    }
}

/// An append-only record of what has been spent.
///
/// Kept trimmed rather than unbounded: the useful questions are "what did that
/// just cost?" and "what has this month cost?", and neither needs a year of
/// individual calls.
public struct SpendLog: Codable, Sendable {
    public var entries: [Spend]
    /// Retained so old totals survive trimming — dropping entries must not
    /// quietly reduce what the learner has been told they spent.
    public var archivedTotal: Double

    public static let keepEntries = 200

    public init(entries: [Spend] = [], archivedTotal: Double = 0) {
        self.entries = entries
        self.archivedTotal = archivedTotal
    }

    public var latest: Spend? { entries.first }

    public var total: Double {
        archivedTotal + entries.reduce(0) { $0 + $1.costUSD }
    }

    public func total(since: Date) -> Double {
        entries.filter { $0.at >= since }.reduce(0) { $0 + $1.costUSD }
    }

    public var today: Double {
        total(since: Calendar.current.startOfDay(for: Date()))
    }

    /// Newest first, trimmed, with anything dropped folded into the total.
    public mutating func record(_ spend: Spend) {
        entries.insert(spend, at: 0)
        guard entries.count > SpendLog.keepEntries else { return }
        let dropped = entries[SpendLog.keepEntries...]
        archivedTotal += dropped.reduce(0) { $0 + $1.costUSD }
        entries = Array(entries.prefix(SpendLog.keepEntries))
    }

    /// Costs are fractions of a cent, and rounding them to two places would
    /// show most calls as $0.00 — which reads as free.
    public static func format(_ amount: Double) -> String {
        if amount == 0 { return "$0" }
        if amount < 0.01 { return String(format: "$%.4f", amount) }
        if amount < 1 { return String(format: "$%.3f", amount) }
        return String(format: "$%.2f", amount)
    }
}
