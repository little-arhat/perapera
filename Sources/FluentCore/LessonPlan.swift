import Foundation

/// How big a lesson should be, given what was asked for and who is asking.
///
/// Pure, and shared: the generator prompt and the on-screen preview must agree,
/// and the only way to guarantee that is one implementation. It previously
/// lived privately inside `LessonService`, so the UI could describe the request
/// only in words — "Varied", "Drill" — while the numbers those words meant were
/// invisible. That is how a lesson generated as `light` (3 per set) gets read as
/// the app ignoring a request for `drill`.
public struct LessonPlan: Equatable, Sendable {
    /// Distinct points the lesson touches.
    public let exercises: Int
    /// Repetitions of each.
    public let itemsPerSet: Int
    public let minutes: Int

    public var items: Int { exercises * itemsPerSet }

    public init(exercises: Int, itemsPerSet: Int, minutes: Int) {
        self.exercises = exercises
        self.itemsPerSet = itemsPerSet
        self.minutes = minutes
    }

    /// Breadth from `size`, depth from `depth`, nudged by level and experience.
    ///
    /// - Parameter dueCount: review mode must cover what is due or the schedule
    ///   slips; due items are spread across sets rather than each becoming an
    ///   exercise of its own.
    public static func plan(
        size: LessonSpec.Size,
        depth: LessonSpec.Depth,
        level: String,
        totalSessions: Int,
        mode: LessonSpec.Mode,
        dueCount: Int
    ) -> LessonPlan {
        let levelBonus = switch level.uppercased() {
        case "A1": 0
        case "A2": 2
        case "B1": 4
        case "B2": 6
        default: 8
        }
        let experienceBonus = min(4, totalSessions / 15)

        let base = switch size {
        case .small: 3
        case .medium: 5
        case .large: 8
        }
        let perSet = depth.itemsPerSet
        let exercises = base + levelBonus / 2 + experienceBonus / 2
        let dueFloor = mode == .review ? dueCount / max(1, perSet) : 0
        let count = min(12, max(exercises, dueFloor))
        let items = count * perSet
        return LessonPlan(
            exercises: count, itemsPerSet: perSet, minutes: max(5, items * 5 / 4))
    }

    /// One line the learner can read before spending anything.
    public var summary: String {
        "\(exercises) exercises × \(itemsPerSet) items ≈ \(items) questions, about \(minutes) min"
    }
}
