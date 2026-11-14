import Foundation

/// The payload `update-db.py` consumes.
///
/// Field names are snake_case to match the documented schema exactly (see
/// `docs/DB_SCRIPTS.md`) -- deliberately, rather than mapping through
/// CodingKeys. This type IS the wire format, and a name that differs from the
/// wire is a name that can silently drift from it.
///
/// It lives in PeraperaCore rather than beside `FluentStore` so the contract can
/// be tested without spawning anything.
public struct SessionReport: Encodable {
    public struct SkillScore: Encodable {
        public let exercises: Int
        public let correct: Int
        public let time_minutes: Int

        public init(exercises: Int, correct: Int, time_minutes: Int) {
            self.exercises = exercises
            self.correct = correct
            self.time_minutes = time_minutes
        }
    }

    public struct TrackedError: Encodable {
        public let pattern_id: String
        public let category: String
        public let subcategory: String?
        public let your_answer: String
        public let correct_answer: String
        public let context: String?
        public let severity: String
        public let difficulty_score: Double?
        public let notes: String?

        public init(
            pattern_id: String, category: String, subcategory: String?,
            your_answer: String, correct_answer: String, context: String?,
            severity: String, difficulty_score: Double?, notes: String?
        ) {
            self.pattern_id = pattern_id
            self.category = category
            self.subcategory = subcategory
            self.your_answer = your_answer
            self.correct_answer = correct_answer
            self.context = context
            self.severity = severity
            self.difficulty_score = difficulty_score
            self.notes = notes
        }
    }

    public struct NewVocabulary: Encodable {
        public let item_id: String
        public let item_type: String
        public let content: String
        public let answer: String
        public let category: String?
        public let difficulty: String?
        public let initial_quality: Int?
        public let priority: String?

        public init(
            item_id: String, item_type: String, content: String, answer: String,
            category: String?, difficulty: String?, initial_quality: Int?,
            priority: String?
        ) {
            self.item_id = item_id
            self.item_type = item_type
            self.content = content
            self.answer = answer
            self.category = category
            self.difficulty = difficulty
            self.initial_quality = initial_quality
            self.priority = priority
        }
    }

    /// How one grammar point went this session.
    ///
    /// The counterpart of `TrackedError`: that one says what the learner got
    /// wrong, this one says how often they got it right. `pattern_id` shares a
    /// namespace with `TrackedError.pattern_id` deliberately, so one id names
    /// the same point on both sides and `mastery-db.patterns` can be read
    /// beside `mistakes-db.error_patterns`.
    ///
    /// Measured, not judged, so the app supplies it: it is a count of answers,
    /// which is the app's half of the split.
    public struct PatternResult: Encodable {
        public let pattern_id: String
        public let attempts: Int
        public let correct: Int

        public init(pattern_id: String, attempts: Int, correct: Int) {
            self.pattern_id = pattern_id
            self.attempts = attempts
            self.correct = correct
        }
    }

    public struct ReviewResult: Encodable {
        public let item_id: String
        public let quality: Int

        public init(item_id: String, quality: Int) {
            self.item_id = item_id
            self.quality = quality
        }
    }

    public let session_id: String
    public let date: String
    public let duration_minutes: Int
    public let command_used: String
    public let skills_practiced: [String]
    public let skill_scores: [String: SkillScore]
    public let errors: [TrackedError]
    public let new_vocabulary: [NewVocabulary]
    public let review_results: [ReviewResult]
    public let pattern_results: [PatternResult]
    public let topics_covered: [String]
    public let breakthroughs: [String]
    public let focus_next_session: [String]
    public let session_notes: String
    public let milestones: [String]

    public init(
        session_id: String,
        date: String,
        duration_minutes: Int,
        command_used: String,
        skills_practiced: [String],
        skill_scores: [String: SkillScore],
        errors: [TrackedError],
        new_vocabulary: [NewVocabulary],
        review_results: [ReviewResult],
        pattern_results: [PatternResult],
        topics_covered: [String],
        breakthroughs: [String],
        focus_next_session: [String],
        session_notes: String,
        milestones: [String]
    ) {
        self.session_id = session_id
        self.date = date
        self.duration_minutes = duration_minutes
        self.command_used = command_used
        self.skills_practiced = skills_practiced
        self.skill_scores = skill_scores
        self.errors = errors
        self.new_vocabulary = new_vocabulary
        self.review_results = review_results
        self.pattern_results = pattern_results
        self.topics_covered = topics_covered
        self.breakthroughs = breakthroughs
        self.focus_next_session = focus_next_session
        self.session_notes = session_notes
        self.milestones = milestones
    }
}

extension SessionReport {
    /// Tallies answers per grammar point.
    ///
    /// Counted in items with partial credit, where `skill_scores` counts
    /// exercises passed. The two granularities differ on purpose: a set of
    /// nine is nine answers on one point, and scoring it as a single pass
    /// throws away the repetition the set exists for.
    ///
    /// `score` returns nil for an exercise the learner never answered, which
    /// is not the same as answering it wrongly and must not be counted as
    /// either.
    public static func patternResults(
        of exercises: [Exercise], score: (Exercise) -> Int?
    ) -> [PatternResult] {
        var tallies: [String: (attempts: Int, correct: Int)] = [:]
        for exercise in exercises {
            guard let pattern = exercise.pattern, let score = score(exercise) else {
                continue
            }
            let items = exercise.itemCount
            let previous = tallies[pattern] ?? (0, 0)
            tallies[pattern] = (
                previous.attempts + items,
                previous.correct + (max(0, min(10, score)) * items + 5) / 10)
        }
        return tallies
            .map { PatternResult(pattern_id: $0.key, attempts: $0.value.attempts,
                                 correct: $0.value.correct) }
            .sorted { $0.pattern_id < $1.pattern_id }
    }
}
