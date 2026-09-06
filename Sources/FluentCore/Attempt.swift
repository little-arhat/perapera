import Foundation

/// A lesson plus what the learner did with it. Lessons accrete rather than
/// mutate in place: the same file records the generated material, the answers,
/// and eventually the teacher's feedback, so the archive can always show what
/// actually happened rather than a summary of it.
public struct LessonRecord: Codable, Sendable, Identifiable {
    public enum State: String, Codable, Sendable, CaseIterable {
        /// Generated, not yet started.
        case generated
        /// Some answers given; can be picked up again.
        case inProgress
        /// Every exercise answered, not yet sent to the teacher. This is the
        /// state a lesson finished offline sits in.
        case completed
        /// The teacher graded it, but Fluent's databases have not been written
        /// yet. A real state, not a transient one: grading costs a paid call, so
        /// it is persisted the moment it arrives. If the app dies here, the
        /// feedback survives and only the write is retried.
        case graded
        /// Written through to Fluent's databases. Terminal.
        case submitted
    }

    public internal(set) var lesson: Lesson
    public var state: State
    public var answers: [String: Answer]         // exercise id → answer
    public var verdicts: [String: Verdict]       // exercise id → locally-decided verdict
    /// A label the learner gave this lesson, e.g. "plane — counters".
    ///
    /// Deliberately on the record rather than on `Lesson`. `Lesson` is the
    /// generated artifact and does not change; the name is the learner's, so it
    /// can be added or corrected long after generation. It is also never sent
    /// to the model — `LessonSpec.focus` is the instruction, this is the label.
    /// Exercise id → image file name, for recognition exercises.
    ///
    /// On the record rather than the lesson: the lesson is what the model
    /// returned, the images are what this machine then built from it.
    public var images: [String: String] = [:]
    public var name: String?
    /// A note to self: why this lesson exists, when to do it.
    public var note: String?
    public var startedAt: Date?
    public var finishedAt: Date?
    /// Time actually spent answering, accumulated between interactions.
    ///
    /// Wall-clock from first open to last answer is not study time: a lesson
    /// left open overnight would log twenty-three hours and permanently skew
    /// Fluent's totals. Gaps longer than `idleThreshold` are treated as the
    /// learner having walked away.
    public var activeSeconds: TimeInterval = 0
    public var feedback: Feedback?
    /// The Fluent session id this became, once submitted.
    public var sessionId: String?

    public var id: String { lesson.id }

    private enum CodingKeys: String, CodingKey {
        case lesson, state, answers, verdicts, startedAt, finishedAt
        case activeSeconds, feedback, sessionId, name, note, images
    }

    /// Records written before a field existed must still open. The archive's
    /// obligation is to read back everything it ever wrote.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lesson = try c.decode(Lesson.self, forKey: .lesson)
        state = try c.decode(State.self, forKey: .state)
        answers = try c.decodeIfPresent([String: Answer].self, forKey: .answers) ?? [:]
        verdicts = try c.decodeIfPresent([String: Verdict].self, forKey: .verdicts) ?? [:]
        images = try c.decodeIfPresent([String: String].self, forKey: .images) ?? [:]
        name = try c.decodeIfPresent(String.self, forKey: .name)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        activeSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .activeSeconds) ?? 0
        feedback = try c.decodeIfPresent(Feedback.self, forKey: .feedback)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
    }

    public init(lesson: Lesson) {
        self.lesson = lesson
        self.state = .generated
        self.answers = [:]
        self.verdicts = [:]
    }

    /// A pause longer than this is someone leaving, not someone thinking.
    public static let idleThreshold: TimeInterval = 5 * 60

    /// Adds the time since the last interaction, ignoring idle gaps.
    public mutating func recordActivity(since last: Date, now: Date = Date()) {
        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0, elapsed < LessonRecord.idleThreshold else { return }
        activeSeconds += elapsed
    }

    /// Minutes spent, rounded up to 1 -- Fluent's stats treat 0-minute sessions
    /// as missing data.
    public var durationMinutes: Int {
        if activeSeconds > 0 { return max(1, Int((activeSeconds / 60).rounded())) }
        // Records written before active time was tracked: fall back to
        // wall-clock, but capped, so an overnight gap cannot poison the totals.
        guard let startedAt, let finishedAt else { return 0 }
        let wallClock = finishedAt.timeIntervalSince(startedAt)
        let plausible = Double(lesson.estimatedMinutes * 3 * 60)
        return max(1, Int((min(wallClock, plausible) / 60).rounded()))
    }

    /// What to call this lesson in a list. The learner's name when they gave
    /// one, otherwise the generated title.
    public var displayTitle: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false ? trimmed! : lesson.title)
    }

    /// A copy without the named exercises.
    ///
    /// Used when an exercise cannot be built — its picture failed verification,
    /// or no key was configured. Removing it is better than showing an
    /// unanswerable question, and better than discarding the whole lesson for
    /// one bad image.
    public func droppingExercises(_ ids: [String]) -> LessonRecord {
        guard !ids.isEmpty else { return self }
        let removed = Set(ids)
        var copy = self
        copy.lesson = Lesson(
            id: lesson.id, title: lesson.title, focus: lesson.focus,
            estimatedMinutes: lesson.estimatedMinutes, preamble: lesson.preamble,
            exercises: lesson.exercises.filter { !removed.contains($0.id) },
            spec: lesson.spec, generatedAt: lesson.generatedAt)
        for id in removed {
            copy.answers[id] = nil
            copy.verdicts[id] = nil
            copy.images[id] = nil
        }
        return copy
    }

    /// How many photographs this lesson carries, for a glance at a row.
    public var photoCount: Int { images.count }

    /// Whether this lesson still owes work to Fluent. Both states offer the
    /// same "Finish" action; what differs is how much of it is left to do.
    public var awaitsSubmission: Bool {
        state == .completed || state == .graded
    }

    public var exercisesNeedingTeacher: [Exercise] {
        lesson.exercises.filter { !$0.isAutoGradable }
    }

    /// The whole lesson's score once graded: local verdicts and the teacher's
    /// marks together.
    ///
    /// `autoGradedScore` deliberately counts only what the app decided, so it
    /// can be shown honestly before submission. After grading that is the wrong
    /// number to display — it silently omits every written answer.
    public var finalScore: (correct: Int, total: Int)? {
        guard let feedback else { return nil }
        let teacher = Dictionary(
            feedback.graded.map { ($0.exerciseId, $0.score) },
            uniquingKeysWith: { first, _ in first })

        var correct = 0
        var total = 0
        for exercise in lesson.exercises {
            if let verdict = verdicts[exercise.id] {
                total += 1
                if verdict.isCorrect { correct += 1 }
            } else if let score = teacher[exercise.id] {
                total += 1
                if score >= 6 { correct += 1 }
            }
        }
        return total > 0 ? (correct, total) : nil
    }

    /// Locally-known accuracy. Excludes teacher-graded exercises, so it is a
    /// floor on the final number, not the final number itself.
    public var autoGradedScore: (correct: Int, total: Int) {
        let graded = lesson.exercises.filter(\.isAutoGradable)
        let correct = graded.reduce(into: 0) { acc, ex in
            if verdicts[ex.id]?.isCorrect == true { acc += 1 }
        }
        return (correct, graded.count)
    }
}

/// The teacher's judgement on a finished lesson. Mirrors
/// `Schemas/feedback.schema.json`.
public struct Feedback: Codable, Sendable {
    public struct Graded: Codable, Sendable {
        public let exerciseId: String
        public let score: Int
        public let comment: String
        public let correctVersion: String?
    }

    public struct TrackedError: Codable, Sendable {
        public let patternId: String
        public let category: String
        public let subcategory: String?
        public let yourAnswer: String
        public let correctAnswer: String
        public let context: String?
        public let severity: String
        public let difficultyScore: Double?
        public let notes: String?
    }

    public struct NewVocabulary: Codable, Sendable {
        public let itemId: String
        public let itemType: String
        public let content: String
        public let answer: String
        public let category: String?
        public let difficulty: String?
        public let initialQuality: Int?
        public let priority: String?
        /// Reading in kana, for an entry written with kanji.
        public let reading: String?
        /// The word in use — the half of a definition that survives.
        public let example: String?
        public let exampleGloss: String?
    }

    public let graded: [Graded]
    public let errors: [TrackedError]?
    public let newVocabulary: [NewVocabulary]?
    public let breakthroughs: [String]?
    public let focusNextSession: [String]?
    public let sessionNotes: String
    public let milestones: [String]?
    public let overallComment: String?
}
