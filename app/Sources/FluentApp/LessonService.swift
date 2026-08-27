import Foundation
import FluentCore

/// Loads the prompt and schema files that ship with the app.
struct ResourceLoader {
    let pluginRoot: URL

    /// Prefers the files in the repo when they are there, so editing a prompt
    /// takes effect without rebuilding; falls back to the copies inside the app
    /// bundle for an installed build.
    func text(_ relativePath: String) throws -> String {
        let repoCopy = pluginRoot.appending(path: "app/Sources/FluentApp/Resources/\(relativePath)")
        if let text = try? String(contentsOf: repoCopy, encoding: .utf8) {
            return text
        }
        let name = (relativePath as NSString).lastPathComponent
        let subdirectory = (relativePath as NSString).deletingLastPathComponent
        guard let url = Bundle.module.url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: (name as NSString).pathExtension,
            subdirectory: subdirectory)
        else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// Turns Fluent's state into a prompt, and a finished lesson into a session
/// report. All the judgement about *what to ask for* and *what to record* lives
/// here, in one place, rather than being spread across views.
@MainActor
struct LessonService {
    let claude: ClaudeClient
    let store: FluentStore
    let lessons: LessonStore
    let resources: ResourceLoader

    // MARK: - Generation

    /// `seedItems` names specific saved items the lesson must drill, for
    /// deliberate practice of a list. Empty means the usual selection.
    func generate(
        spec: LessonSpec, seedItems: [SavedItem] = [],
        progress: (@Sendable (ClaudeClient.Progress) -> Void)? = nil
    ) async throws -> LessonRecord {
        let snapshot = try await store.load()
        let prompt = try buildGenerationPrompt(
            spec: spec, snapshot: snapshot, seedItems: seedItems)
        let schema = try resources.text("Schemas/lesson.schema.json")

        let generated = try await claude.request(
            GeneratedLesson.self, prompt: prompt, schema: schema, progress: progress)

        let lesson = Lesson(
            id: newLessonID(spec: spec),
            title: generated.title,
            focus: generated.focus,
            estimatedMinutes: generated.estimatedMinutes,
            preamble: generated.preamble,
            exercises: generated.exercises,
            spec: spec,
            generatedAt: Date()
        )
        // Reject here, where a retry is free, rather than showing an
        // unanswerable exercise. The archive decoder stays lenient by design.
        let defects = lesson.validate()
        guard defects.isEmpty else {
            throw GenerationDefect(defects: defects)
        }

        let record = LessonRecord(lesson: lesson)
        try lessons.save(record)
        return record
    }

    /// What the schema produces, before the app adds its own identity and
    /// provenance. Separate from `Lesson` so the model is never asked to invent
    /// an id or a timestamp -- facts the app already knows.
    private struct GeneratedLesson: Decodable {
        let title: String
        let focus: String
        let estimatedMinutes: Int
        let preamble: String?
        let exercises: [Exercise]
    }

    private func newLessonID(spec: LessonSpec) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "lesson-\(formatter.string(from: Date()))-\(spec.mode.rawValue)"
    }

    private func buildGenerationPrompt(
        spec: LessonSpec, snapshot: FluentStore.Snapshot, seedItems: [SavedItem]
    ) throws -> String {
        let learner = snapshot.databases.learner_profile.learner
        let target = exerciseTarget(spec: spec, snapshot: snapshot)

        let due = snapshot.computed.due_review_items.compactMap {
            snapshot.databases.spaced_repetition.items[$0]
        }
        let dueText: String
        if seedItems.isEmpty {
            dueText = due.isEmpty ? "(none due)" : due.map {
                "- \($0.id) [\($0.type ?? "item"), \($0.priority ?? "medium")] \($0.content) → \($0.answer)"
            }.joined(separator: "\n")
        } else {
            // Deliberate practice of a chosen list: these replace the due set,
            // and every one of them must be exercised.
            dueText = "The learner asked to practice these specific saved items. "
                + "Cover EVERY one:\n"
                + seedItems.map {
                    "- \($0.id) [\($0.kind.rawValue)] \($0.content) → \($0.gloss)"
                }.joined(separator: "\n")
        }

        let patterns = snapshot.databases.mistakes_db.error_patterns
            .sorted { ($0.value.frequency ?? 0) > ($1.value.frequency ?? 0) }
            .prefix(12)
        let patternText = patterns.isEmpty ? "(none recorded yet)" : patterns.map {
            "- \($0.key) [\($0.value.category ?? "?"), seen \($0.value.frequency ?? 0)×]"
                + ($0.value.notes.map { n in ": \(n)" } ?? "")
        }.joined(separator: "\n")

        return try resources.text("Prompts/generate-lesson.md")
            .replacingOccurrences(of: "{{NAME}}", with: learner.name)
            .replacingOccurrences(of: "{{TARGET_LANGUAGE}}", with: learner.target_language)
            .replacingOccurrences(of: "{{NATIVE_LANGUAGE}}", with: learner.native_language ?? "unknown")
            .replacingOccurrences(of: "{{OTHER_LANGUAGES}}", with: (learner.other_languages ?? []).joined(separator: ", "))
            .replacingOccurrences(of: "{{EXPLANATION_LANGUAGE}}", with: learner.explanation_language ?? "English")
            .replacingOccurrences(of: "{{CURRENT_LEVEL}}", with: learner.current_level)
            .replacingOccurrences(of: "{{TARGET_LEVEL}}", with: learner.target_level)
            .replacingOccurrences(of: "{{MOTIVATION}}", with: learner.motivation ?? "general fluency")
            .replacingOccurrences(of: "{{LEARNING_STYLE}}", with: learner.learning_style ?? "balanced")
            .replacingOccurrences(of: "{{MODE}}", with: spec.mode.rawValue)
            .replacingOccurrences(of: "{{SIZE}}", with: spec.size.rawValue)
            .replacingOccurrences(of: "{{TARGET_EXERCISES}}", with: String(target.exercises))
            .replacingOccurrences(of: "{{ITEMS_PER_SET}}", with: String(target.itemsPerSet))
            .replacingOccurrences(of: "{{TARGET_MINUTES}}", with: String(target.minutes))
            .replacingOccurrences(of: "{{FOCUS}}", with: spec.focus.isEmpty ? "(no specific focus — choose what serves the learner most)" : spec.focus)
            .replacingOccurrences(of: "{{ERROR_PATTERNS}}", with: patternText)
            .replacingOccurrences(of: "{{DUE_ITEMS}}", with: dueText)
            .replacingOccurrences(of: "{{RECENT_NOTES}}", with: "(see error patterns above)")
    }

    /// Size means "how much", and how much scales with the learner. A medium
    /// lesson at A1 is not a medium lesson at B1, so the baseline grows with
    /// level and with how many sessions are behind them.
    private func exerciseTarget(
        spec: LessonSpec, snapshot: FluentStore.Snapshot
    ) -> (exercises: Int, itemsPerSet: Int, minutes: Int) {
        let level = snapshot.databases.learner_profile.learner.current_level.uppercased()
        let levelBonus = switch level {
        case "A1": 0
        case "A2": 2
        case "B1": 4
        case "B2": 6
        default: 8
        }
        let experienceBonus = min(4, snapshot.databases.learner_profile.total_sessions / 15)

        // Breadth: how many distinct points the lesson touches.
        let base = switch spec.size {
        case .small: 3
        case .medium: 5
        case .large: 8
        }
        let exercises = base + levelBonus / 2 + experienceBonus / 2
        // Review mode must cover what is due, or the schedule slips. Due items
        // are spread across sets rather than each becoming its own exercise.
        let dueFloor = spec.mode == .review
            ? snapshot.computed.due_reviews_count / spec.depth.itemsPerSet : 0
        let count = min(12, max(exercises, dueFloor))
        let items = count * spec.depth.itemsPerSet
        return (count, spec.depth.itemsPerSet, max(5, items * 5 / 4))
    }

    // MARK: - Submission

    /// `saved` are items the learner starred and that have not yet been handed
    /// to Fluent; they enter spaced repetition with this session.
    func submit(
        _ record: LessonRecord, saved: [SavedItem] = [],
        progress: (@Sendable (ClaudeClient.Progress) -> Void)? = nil
    ) async throws -> LessonRecord {
        let snapshot = try await store.load()
        // Only built when grading is actually needed.
        let prompt = record.feedback == nil
            ? try buildGradingPrompt(record: record, snapshot: snapshot) : ""
        let schema = record.feedback == nil
            ? try resources.text("Schemas/feedback.schema.json") : ""

        var updated = record
        let feedback: Feedback
        if let existing = record.feedback {
            // Already graded by an attempt that failed before the write.
            // Re-grading would charge for the same judgement twice and could
            // return a different one, which is worse than useless.
            feedback = existing
        } else {
            feedback = try await claude.request(
                Feedback.self, prompt: prompt, schema: schema, progress: progress)
            // Persist before writing to Fluent: grading is the expensive half,
            // and a crash between the two must not throw it away.
            updated.feedback = feedback
            updated.state = .graded
            updated.sessionId = snapshot.computed.next_session_id
            try lessons.save(updated)
        }
        updated.feedback = feedback
        updated.sessionId = updated.sessionId ?? snapshot.computed.next_session_id

        let report = buildReport(
            record: updated, feedback: feedback,
            sessionId: updated.sessionId ?? snapshot.computed.next_session_id,
            date: snapshot.computed.today,
            saved: saved)
        _ = try await store.submit(report)

        updated.state = .submitted
        try lessons.save(updated)
        return updated
    }

    private func buildGradingPrompt(
        record: LessonRecord, snapshot: FluentStore.Snapshot
    ) throws -> String {
        let learner = snapshot.databases.learner_profile.learner

        var lines: [String] = []
        for exercise in record.lesson.exercises {
            let answer = record.answers[exercise.id]
            lines.append("### \(exercise.id) — \(exercise.skill.rawValue)")
            lines.append("Prompt: \(exercise.prompt)")
            if let instruction = exercise.instruction {
                lines.append("Instruction: \(instruction)")
            }
            lines.append("Learner answered: \(describe(answer, for: exercise))")
            if let verdict = record.verdicts[exercise.id] {
                lines.append("autoGraded: \(verdict.isCorrect ? "correct" : "incorrect") "
                    + "(\(verdict.score)/10). Expected: \(verdict.correctVersion)")
            } else {
                lines.append("needsGrading. Reference answer: \(reference(for: exercise))")
            }
            lines.append("")
        }

        let patterns = snapshot.databases.mistakes_db.error_patterns
            .sorted { ($0.value.frequency ?? 0) > ($1.value.frequency ?? 0) }
            .prefix(15)
            .map { "- \($0.key) [\($0.value.category ?? "?"), seen \($0.value.frequency ?? 0)×]" }
            .joined(separator: "\n")

        return try resources.text("Prompts/grade-lesson.md")
            .replacingOccurrences(of: "{{NAME}}", with: learner.name)
            .replacingOccurrences(of: "{{TARGET_LANGUAGE}}", with: learner.target_language)
            .replacingOccurrences(of: "{{NATIVE_LANGUAGE}}", with: learner.native_language ?? "unknown")
            .replacingOccurrences(of: "{{OTHER_LANGUAGES}}", with: (learner.other_languages ?? []).joined(separator: ", "))
            .replacingOccurrences(of: "{{EXPLANATION_LANGUAGE}}", with: learner.explanation_language ?? "English")
            .replacingOccurrences(of: "{{CURRENT_LEVEL}}", with: learner.current_level)
            .replacingOccurrences(of: "{{TARGET_LEVEL}}", with: learner.target_level)
            .replacingOccurrences(of: "{{ERROR_PATTERNS}}", with: patterns.isEmpty ? "(none recorded yet)" : patterns)
            .replacingOccurrences(of: "{{ATTEMPT}}", with: lines.joined(separator: "\n"))
    }

    private func describe(_ answer: Answer?, for exercise: Exercise) -> String {
        guard let answer else { return "(not answered)" }
        switch answer {
        case let .text(text):
            return text.isEmpty ? "(blank)" : text
        case let .choice(index):
            if case let .multipleChoice(options, _) = exercise.content,
               options.indices.contains(index) {
                return "\(options[index]) (option \(index + 1))"
            }
            return "option \(index + 1)"
        case let .order(order):
            if case let .reorder(tokens, _) = exercise.content {
                return order.filter(tokens.indices.contains).map { tokens[$0] }.joined(separator: " ")
            }
            return order.map(String.init).joined(separator: ",")
        case let .matches(picks):
            if case let .matching(pairs) = exercise.content {
                return zip(pairs, picks).map { pair, pick in
                    let right = pairs.indices.contains(pick) ? pairs[pick].right : "?"
                    return "\(pair.left)→\(right)"
                }.joined(separator: ", ")
            }
            return picks.map(String.init).joined(separator: ",")
        case let .texts(answers):
            if case let .set(items) = exercise.content {
                return zip(items.indices, answers).map { index, typed in
                    "\(index + 1). \(typed.isEmpty ? "(blank)" : typed)"
                }.joined(separator: "  |  ")
            }
            return answers.joined(separator: " | ")
        case let .selfRated(rating):
            return "self-rated \(rating)/5"
        case .skipped:
            return "(skipped)"
        }
    }

    private func reference(for exercise: Exercise) -> String {
        switch exercise.content {
        case let .translation(reference), let .freeResponse(reference):
            reference
        case let .cloze(accepted), let .digitEntry(accepted):
            // A cloze reaches the teacher only when the answer was a close
            // call, so the accepted list has to come with it.
            "accepted: " + accepted.joined(separator: " / ")
        case let .set(items):
            items.enumerated().map { index, item in
                "\(index + 1). \(item.prompt) → " + item.acceptedAnswers.joined(separator: " / ")
            }.joined(separator: "\n")
        default:
            ""
        }
    }

    /// Builds the `update-db.py` payload.
    ///
    /// The split is deliberate: the app supplies every fact it can measure
    /// (counts, durations, which items were reviewed and at what quality), and
    /// the teacher supplies only judgement (errors worth tracking, notes,
    /// breakthroughs). Neither is asked for the other's half.
    private func buildReport(
        record: LessonRecord, feedback: Feedback, sessionId: String, date: String,
        saved: [SavedItem] = []
    ) -> SessionReport {
        var scores: [String: SessionReport.SkillScore] = [:]
        var reviews: [SessionReport.ReviewResult] = []

        let teacherScores = Dictionary(
            feedback.graded.map { ($0.exerciseId, $0.score) },
            uniquingKeysWith: { first, _ in first })

        for exercise in record.lesson.exercises {
            let score = record.verdicts[exercise.id]?.score ?? teacherScores[exercise.id]
            guard let score else { continue }

            let key = exercise.skill.rawValue
            let previous = scores[key] ?? .init(exercises: 0, correct: 0, time_minutes: 0)
            scores[key] = .init(
                exercises: previous.exercises + 1,
                correct: previous.correct + (score >= 6 ? 1 : 0),
                time_minutes: previous.time_minutes)

            for itemId in exercise.reviewItemIds {
                reviews.append(.init(item_id: itemId, quality: min(5, max(0, score / 2))))
            }
        }

        // Spread the measured duration across skills by exercise count, so the
        // per-skill minutes add up to the real elapsed time.
        let totalExercises = max(1, scores.values.reduce(0) { $0 + $1.exercises })
        let duration = max(1, record.durationMinutes)
        for (key, value) in scores {
            scores[key] = .init(
                exercises: value.exercises,
                correct: value.correct,
                time_minutes: max(1, duration * value.exercises / totalExercises))
        }

        // One review_results entry per item: a repeated id would run SM-2 twice
        // on the same item in one session and overstate its interval.
        var bestQuality: [String: Int] = [:]
        for review in reviews {
            bestQuality[review.item_id] = min(
                bestQuality[review.item_id] ?? review.quality, review.quality)
        }

        return SessionReport(
            session_id: sessionId,
            date: date,
            duration_minutes: duration,
            command_used: "fluent-app",
            skills_practiced: Array(scores.keys).sorted(),
            skill_scores: scores,
            errors: (feedback.errors ?? []).map {
                .init(pattern_id: $0.patternId, category: $0.category,
                      subcategory: $0.subcategory, your_answer: $0.yourAnswer,
                      correct_answer: $0.correctAnswer, context: $0.context,
                      severity: $0.severity, difficulty_score: $0.difficultyScore,
                      notes: $0.notes)
            },
            new_vocabulary: (feedback.newVocabulary ?? []).map {
                .init(item_id: $0.itemId, item_type: $0.itemType, content: $0.content,
                      answer: $0.answer, category: $0.category, difficulty: $0.difficulty,
                      initial_quality: $0.initialQuality, priority: $0.priority)
            } + saved.map {
                // Starred items enter spaced repetition on the same path as
                // anything else, so there is one schedule, not two. Quality 2
                // because deliberately saving a word means it was not yet known.
                .init(item_id: $0.id, item_type: $0.kind.fluentItemType,
                      content: $0.content, answer: $0.gloss,
                      category: "saved_\($0.kind.rawValue)", difficulty: nil,
                      initial_quality: 2, priority: "high")
            },
            review_results: bestQuality.map { .init(item_id: $0.key, quality: $0.value) }
                .sorted { $0.item_id < $1.item_id },
            topics_covered: [record.lesson.focus],
            breakthroughs: feedback.breakthroughs ?? [],
            focus_next_session: feedback.focusNextSession ?? [],
            session_notes: feedback.sessionNotes,
            milestones: feedback.milestones ?? []
        )
    }
}
