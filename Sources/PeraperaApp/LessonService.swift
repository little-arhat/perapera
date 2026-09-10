import Foundation
import PeraperaCore

/// Loads the prompt and schema files that ship with the app.
///
/// The bundle is the source. The old repo-first lookup pointed at
/// `app/Sources/PeraperaApp/Resources/`, a path that stopped existing when the app
/// moved to the repository root, so it had already silently become
/// bundle-only. An explicit override restores editing a prompt without a rebuild.
struct ResourceLoader {
    /// Set `FLUENT_APP_RESOURCES` to `Sources/PeraperaApp/Resources` in a checkout.
    var override: URL? = ProcessInfo.processInfo.environment["FLUENT_APP_RESOURCES"]
        .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }

    func text(_ relativePath: String) throws -> String {
        if let override,
           let text = try? String(contentsOf: override.appending(path: relativePath),
                                  encoding: .utf8) {
            return text
        }
        let name = (relativePath as NSString).lastPathComponent
        let directory = (relativePath as NSString).deletingLastPathComponent
        // nil, not "": a resource at the bundle root has no subdirectory, and an
        // empty string is not the same thing.
        guard let url = Bundle.module.url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: (name as NSString).pathExtension,
            subdirectory: directory.isEmpty ? nil : directory)
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
    /// Writes lessons. The high-volume call.
    let claude: ClaudeClient
    /// Reads answers. A different job, and priced separately.
    let grader: ClaudeClient
    let store: FluentStore
    let lessons: LessonStore
    let resources: ResourceLoader
    /// Where the teacher's brief is read from.
    let fluentRoot: URL
    /// Nil when no OpenRouter key is configured, in which case recognition
    /// exercises are dropped rather than shipped without their picture.
    var images: ImagePipeline?

    // MARK: - Generation

    /// `seedItems` names specific saved items the lesson must drill, for
    /// deliberate practice of a list. Empty means the usual selection.
    func generate(
        spec: LessonSpec, seedItems: [SavedItem] = [],
        recent: [LessonRecord] = [],
        progress: (@Sendable (ClaudeClient.Progress) -> Void)? = nil,
        onSpend: (@Sendable (String, Double, String) -> Void)? = nil
    ) async throws -> LessonRecord {
        let snapshot = try await store.load()
        let prompt = try buildGenerationPrompt(
            spec: spec, snapshot: snapshot, seedItems: seedItems, recent: recent)
        let schema = try resources.text("Schemas/lesson.schema.json")

        let generated = try await claude.request(
            GeneratedLesson.self, prompt: prompt,
            systemPrompt: try TeacherContext.systemPrompt(
                fluentRoot: fluentRoot, call: .generation),
            schema: schema, progress: progress,
            onSpend: { cost, model in onSpend?("Lesson", cost, model) })

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
        // A defective exercise is dropped, not the whole lesson. Every defect
        // names the exercise at fault, so one unanswerable question used to cost
        // a full regeneration -- the same trade the image path already makes,
        // where losing an exercise is the cheapest of the available outcomes.
        //
        // Defects with no exercise to blame, or that would leave nothing to
        // practise, still fail: a lesson of one question is not the sitting the
        // learner asked for.
        let defects = lesson.validate()
        let broken = Set(defects.compactMap(\.exerciseID))
        let survivors = lesson.exercises.filter { !broken.contains($0.id) }
        guard broken.count == defects.count, survivors.count >= 2 else {
            throw GenerationDefect(defects: defects)
        }
        var record = LessonRecord(lesson: lesson).droppingExercises(Array(broken))
        try lessons.save(record)
        record = try await buildImages(for: record, progress: progress, onSpend: onSpend)
        try lessons.save(record)
        return record
    }

    /// Builds and verifies the photograph each recognition exercise needs.
    ///
    /// An exercise whose image cannot be produced *correctly* is dropped from
    /// the lesson rather than shown without one — a recognition exercise with no
    /// picture is unanswerable, and one whose picture spells the word wrong
    /// teaches the wrong letterform. Losing an exercise is the cheapest of the
    /// three outcomes.
    ///
    /// The lesson is saved before this runs, so a crash mid-generation leaves a
    /// usable text lesson rather than nothing.
    private func buildImages(
        for record: LessonRecord,
        progress: (@Sendable (ClaudeClient.Progress) -> Void)?,
        onSpend: (@Sendable (String, Double, String) -> Void)? = nil
    ) async throws -> LessonRecord {
        let needing = record.lesson.exercises.compactMap { exercise -> (Exercise, Exercise.ImageSpec)? in
            exercise.content.imageSpec.map { (exercise, $0) }
        }
        guard !needing.isEmpty else { return record }

        guard let images else {
            // No key: keep the text exercises, drop the ones that need pictures.
            return record.droppingExercises(needing.map(\.0.id))
        }

        var updated = record
        var failed: [String] = []
        let capped = needing.prefix(images.config.maxImagesPerLesson)
        if needing.count > capped.count {
            failed += needing.dropFirst(capped.count).map(\.0.id)
        }

        for (index, pair) in capped.enumerated() {
            let (exercise, spec) = pair
            let label = "Picture \(index + 1) of \(capped.count)"
            do {
                let built = try await images.build(for: exercise, spec: spec) { note in
                    progress?(.init(phase: .writing, text: "\(label): \(note)",
                                    thinkingTokens: 0))
                }
                let fileName = try lessons.saveImage(
                    built.jpeg, lessonId: record.id, exerciseId: exercise.id)
                updated.images[exercise.id] = fileName
                onSpend?("Picture", built.costUSD, images.config.generationModel)
            } catch {
                failed.append(exercise.id)
            }
        }
        return failed.isEmpty ? updated : updated.droppingExercises(failed)
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
        spec: LessonSpec, snapshot: FluentStore.Snapshot, seedItems: [SavedItem],
        recent: [LessonRecord] = []
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
            .replacingOccurrences(of: "{{TEACHER_PLAN}}", with: teacherPlan(snapshot))
            .replacingOccurrences(of: "{{RECENT_NOTES}}", with: recentNotes(snapshot))
            .replacingOccurrences(of: "{{SKILL_MASTERY}}", with: skillMastery(snapshot))
            .replacingOccurrences(of: "{{IMAGE_BUDGET}}", with: imageBudget(spec))
            .replacingOccurrences(of: "{{RECENT_LESSONS}}", with: recentSummary(recent))
    }

    /// Delegates to `LessonPlan` so the prompt and the on-screen preview cannot
    /// disagree about what was asked for.
    private func exerciseTarget(
        spec: LessonSpec, snapshot: FluentStore.Snapshot
    ) -> (exercises: Int, itemsPerSet: Int, minutes: Int) {
        let plan = LessonPlan.plan(
            size: spec.size,
            depth: spec.depth,
            level: snapshot.databases.learner_profile.learner.current_level,
            totalSessions: snapshot.databases.learner_profile.total_sessions,
            mode: spec.mode,
            dueCount: snapshot.computed.due_reviews_count)
        return (plan.exercises, plan.itemsPerSet, plan.minutes)
    }

    /// What the teacher said to do next, from Fluent's session log.
    ///
    /// The single most valuable input here and previously discarded entirely —
    /// the prompt substituted the literal string "(see error patterns above)".
    /// These lines were written by a teacher looking at the learner's actual
    /// answers, and they are specific in a way no summary of error patterns is:
    /// "the 百-series shifts — listening was the only 0 of the lesson and the
    /// one with real-world cost".
    ///
    /// Newest first, because the most recent instruction has not been acted on
    /// yet by definition.
    private func teacherPlan(_ snapshot: FluentStore.Snapshot) -> String {
        let sessions = snapshot.databases.session_log.sessions.reversed()
        var lines: [String] = []
        for session in sessions {
            guard let focus = session.focus_next_session, !focus.isEmpty else { continue }
            let when = session.date.map { " (after \($0))" } ?? ""
            lines.append(contentsOf: focus.map { "- \($0)\(when)" })
            // Two sessions' worth. Older instructions have usually been
            // overtaken, and a long list stops reading as a priority.
            if lines.count >= 6 { break }
        }
        return lines.isEmpty ? "(nothing recorded yet)" : lines.joined(separator: "\n")
    }

    /// What the last sessions covered and how they went.
    private func recentNotes(_ snapshot: FluentStore.Snapshot) -> String {
        let sessions = snapshot.databases.session_log.sessions.suffix(4).reversed()
        let lines = sessions.map { session -> String in
            let accuracy = session.accuracy.map { " — \(Int($0 * 100))% correct" } ?? ""
            let topics = (session.topics_covered ?? []).joined(separator: "; ")
            return "- \(session.date ?? "?")\(accuracy): \(topics.isEmpty ? "—" : topics)"
        }
        return lines.isEmpty ? "(no sessions yet)" : lines.joined(separator: "\n")
    }

    /// Mastery per skill, 0-5, so the lesson can lean on what is weak.
    private func skillMastery(_ snapshot: FluentStore.Snapshot) -> String {
        guard let skills = snapshot.databases.mastery_db.skills, !skills.isEmpty else {
            return "(not yet assessed)"
        }
        return skills
            .sorted { ($0.value.mastery_level ?? 0) < ($1.value.mastery_level ?? 0) }
            .map { "\($0.key) \($0.value.mastery_level ?? 0)/5" }
            .joined(separator: " · ")
    }

    /// The last few lessons, so the generator can avoid repeating them.
    ///
    /// Without this it has no memory: every request looks like the first, and
    /// the same ticket window comes back for the fifth time because it is the
    /// obvious scene for the learner's stated goal. The setting is not the
    /// point — the grammar is — so what has to vary is the setting.
    private func recentSummary(_ recent: [LessonRecord]) -> String {
        let entries = recent.prefix(6).map { record -> String in
            let focus = record.lesson.focus.isEmpty ? "" : " — \(record.lesson.focus)"
            return "- \(record.lesson.title)\(focus)"
        }
        return entries.isEmpty ? "(none yet)" : entries.joined(separator: "\n")
    }

    /// How many photographs this lesson may use, stated to the generator in
    /// plain terms. Each costs about $0.07, so the cap is a spending decision
    /// and belongs with the learner, not the model.
    private func imageBudget(_ spec: LessonSpec) -> String {
        guard images != nil, spec.photoExercises > 0 else {
            return "None. Do not use the `recognition` kind in this lesson."
        }
        return "Use exactly \(spec.photoExercises) `recognition` exercise(s). "
            + "Each is a real photograph the app will generate and verify."
    }

    // MARK: - Submission

    /// `saved` are items the learner starred and that have not yet been handed
    /// to Fluent; they enter spaced repetition with this session.
    func submit(
        _ record: LessonRecord, saved: [SavedItem] = [],
        progress: (@Sendable (ClaudeClient.Progress) -> Void)? = nil,
        onSpend: (@Sendable (String, Double, String) -> Void)? = nil
    ) async throws -> LessonRecord {
        let snapshot = try await store.load()

        var updated = record
        let feedback: Feedback
        if let existing = record.feedback {
            // Already graded by an attempt that failed before the write.
            // Re-grading would charge for the same judgement twice and could
            // return a different one, which is worse than useless.
            feedback = existing
        } else {
            // Built here, not above: `submit` is called again after a crash
            // between grading and the write, and that path makes no model call.
            // Assembling the brief outside this branch would turn a missing
            // Fluent document into a failure on a path that needs neither.
            feedback = try await grader.request(
                Feedback.self,
                prompt: try buildGradingPrompt(record: record, snapshot: snapshot),
                systemPrompt: try TeacherContext.systemPrompt(
                    fluentRoot: fluentRoot, call: .grading),
                schema: try resources.text("Schemas/feedback.schema.json"),
                progress: progress,
                onSpend: { cost, model in onSpend?("Grading", cost, model) })
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
