import Foundation

/// A generated lesson, as produced by the teacher and stored on disk.
///
/// The JSON contract (`Schemas/lesson.schema.json`) keeps exercise fields flat
/// and optional because models generate flat objects far more reliably than
/// discriminated unions. The boundary validates; the interior gets a real sum
/// type via `Exercise.content`. Tradeoff: one decode-time conversion, in
/// exchange for never threading optionals through the UI.
public struct Lesson: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let focus: String
    public let estimatedMinutes: Int
    public let preamble: String?
    public let exercises: [Exercise]

    /// How the lesson was requested. Kept so the archive can explain itself.
    public let spec: LessonSpec
    public let generatedAt: Date

    /// Questions the learner actually answers — a set of nine counts as nine.
    public var itemCount: Int { exercises.reduce(0) { $0 + $1.itemCount } }

    public init(
        id: String, title: String, focus: String, estimatedMinutes: Int,
        preamble: String?, exercises: [Exercise], spec: LessonSpec, generatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.focus = focus
        self.estimatedMinutes = estimatedMinutes
        self.preamble = preamble
        self.exercises = exercises
        self.spec = spec
        self.generatedAt = generatedAt
    }
}

/// What the learner asked for. A value, not a form.
public struct LessonSpec: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, Sendable, CaseIterable {
        case lesson, review
    }

    /// Size scales the exercise count. The baseline grows with the learner's
    /// level and recent accuracy, so "medium" means more after six months than
    /// it does today.
    public enum Size: String, Codable, Sendable, CaseIterable {
        case small, medium, large

        public var label: String {
            switch self {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            }
        }

        /// What the option means, in one line.
        public var help: String {
            switch self {
            case .small: "3 topics. A short sitting."
            case .medium: "5 topics."
            case .large: "8 topics. Covers the most ground."
            }
        }
    }

    /// How many items each drill repeats.
    ///
    /// Separate from `size` because they answer different questions. `size` is
    /// breadth — how many distinct points the lesson touches. `depth` is
    /// repetition — how many times you practise each one. Many points × few
    /// repetitions is a survey; few points × many repetitions is a drill, and
    /// automaticity comes from the second. Braiding them into one control would
    /// make one of the two unreachable.
    public enum Depth: String, Codable, Sendable, CaseIterable {
        case light, standard, drill

        public var label: String {
            switch self {
            case .light: "Varied"
            case .standard: "Balanced"
            case .drill: "Drill"
            }
        }

        /// The label with what it actually means. "Varied" on its own reads as
        /// a mood; a lesson generated as `light` then looks like the app
        /// ignoring a request for `drill`.
        public var detailedLabel: String { "\(label) · \(itemsPerSet)" }

        public var help: String {
            switch self {
            case .light: "3 questions per topic. More variety, less repetition."
            case .standard: "5 questions per topic."
            case .drill: "9 questions per topic. Builds automaticity."
            }
        }

        /// Items per set.
        public var itemsPerSet: Int {
            switch self {
            case .light: 3
            case .standard: 5
            case .drill: 9
            }
        }
    }

    public let mode: Mode
    public let size: Size
    public let depth: Depth
    public let focus: String
    /// How many photograph-based exercises to include.
    ///
    /// A spending decision, so it is explicit and defaults to none. Each image
    /// costs about $0.07 to make and verify; nothing else in a lesson costs
    /// per-unit, so this is the only control where the number is money.
    public let photoExercises: Int

    public init(
        mode: Mode, size: Size, depth: Depth = .standard, focus: String,
        photoExercises: Int = 0
    ) {
        self.mode = mode
        self.size = size
        self.depth = depth
        self.focus = focus
        self.photoExercises = max(0, photoExercises)
    }

    /// Lessons written before `depth` existed decode as `.standard` rather than
    /// becoming unreadable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decode(Mode.self, forKey: .mode)
        size = try c.decode(Size.self, forKey: .size)
        depth = try c.decodeIfPresent(Depth.self, forKey: .depth) ?? .standard
        focus = try c.decode(String.self, forKey: .focus)
        photoExercises = try c.decodeIfPresent(Int.self, forKey: .photoExercises) ?? 0
    }
}

public struct Exercise: Codable, Sendable, Identifiable {
    public enum Skill: String, Codable, Sendable {
        case vocabulary, grammar, reading, writing, listening, speaking
    }

    public let id: String
    public let skill: Skill
    public let prompt: String
    public let instruction: String?
    public let explanation: String?
    public let audioText: String?
    /// Reading-comprehension text this exercise asks about. Consecutive
    /// exercises may share one passage verbatim; the player shows it once.
    public let passage: String?
    public let reviewItemIds: [String]
    public let content: Content

    /// The exercise's actual shape. Locally-gradable cases carry their answer
    /// key; the two teacher-graded cases carry a reference answer instead.
    public enum Content: Sendable {
        case multipleChoice(options: [String], correctIndex: Int)
        case cloze(accepted: [String])
        case reorder(tokens: [String], correctOrder: [Int])
        case matching(pairs: [Pair])
        case digitEntry(accepted: [String])
        case flashcard(front: String, back: String)
        case translation(reference: String)
        case freeResponse(reference: String)
        /// A numbered drill: several short items under one instruction, the way
        /// a textbook groups practice. Graded item by item with partial credit,
        /// because repetition on one point is the thing that builds fluency and
        /// scoring eight items as one pass/fail throws that signal away.
        case set(items: [SetItem])
        /// Read text off a photograph of the real world.
        ///
        /// The stimulus is an image, generated and verified at lesson build
        /// time. Screen kana and street kana are different perceptual tasks —
        /// brush on a noren, marker on a menu board, weathered enamel — and
        /// only this kind trains the second.
        case recognition(image: ImageSpec, accepted: [String])

        /// Whether the app can decide this without the teacher.
        public var isAutoGradable: Bool {
            switch self {
            case .translation, .freeResponse: false
            default: true
            }
        }

        /// The image this exercise needs built before it can be shown.
        public var imageSpec: ImageSpec? {
            if case let .recognition(image, _) = self { return image }
            return nil
        }
    }

    /// What image to make, and what must be legible in it.
    ///
    /// `targets` is not decoration: it is checked against a read-back of the
    /// finished image, and an image that fails is discarded. A wrong glyph in a
    /// reading drill teaches a wrong letterform, which is worse than no drill.
    public struct ImageSpec: Codable, Sendable, Hashable {
        /// Scene description handed to the image model.
        public let scene: String
        /// Exact strings that must appear in the image.
        public let targets: [String]
        /// Which of the visible text the learner is asked to read.
        public let question: String?

        public init(scene: String, targets: [String], question: String?) {
            self.scene = scene
            self.targets = targets
            self.question = question
        }
    }

    public struct SetItem: Codable, Sendable, Hashable {
        public let prompt: String
        public let acceptedAnswers: [String]
        /// Cue beside the gap -- the dictionary form in "___ (ir)", a counter,
        /// or an English gloss.
        public let hint: String?
        public let explanation: String?

        public init(prompt: String, acceptedAnswers: [String],
                    hint: String?, explanation: String?) {
            self.prompt = prompt
            self.acceptedAnswers = acceptedAnswers
            self.hint = hint
            self.explanation = explanation
        }
    }

    public struct Pair: Codable, Sendable, Hashable {
        public let left: String
        public let right: String
        public init(left: String, right: String) {
            self.left = left
            self.right = right
        }
    }

    public var isAutoGradable: Bool { content.isAutoGradable }

    /// A stand-in for a picture made outside any lesson, so `ImagePipeline`
    /// can take an exercise without a second entry point that would drift.
    public static func placeholder(id: String) -> Exercise {
        Exercise(
            id: id, skill: .reading, prompt: "", instruction: nil,
            explanation: nil, audioText: nil, passage: nil, reviewItemIds: [],
            content: .recognition(
                image: ImageSpec(scene: "", targets: [], question: nil),
                accepted: []))
    }

    init(
        id: String, skill: Skill, prompt: String, instruction: String?,
        explanation: String?, audioText: String?, passage: String?,
        reviewItemIds: [String], content: Content
    ) {
        self.id = id
        self.skill = skill
        self.prompt = prompt
        self.instruction = instruction
        self.explanation = explanation
        self.audioText = audioText
        self.passage = passage
        self.reviewItemIds = reviewItemIds
        self.content = content
    }

    /// Every target-language string this exercise puts on screen.
    ///
    /// Used to decide whether the readings toggle is worth offering. Checking
    /// only `prompt` gets a `set` wrong: its prompt is often the English
    /// instruction while the kanji live in the items.
    public var displayedText: [String] {
        var texts = [prompt, instruction ?? "", passage ?? "", explanation ?? ""]
        switch content {
        case let .multipleChoice(options, _):
            texts += options
        case let .reorder(tokens, _):
            texts += tokens
        case let .matching(pairs):
            texts += pairs.map(\.left) + pairs.map(\.right)
        case let .flashcard(front, back):
            texts += [front, back]
        case let .set(items):
            texts += items.flatMap { [$0.prompt, $0.hint ?? "", $0.explanation ?? ""] }
        case let .translation(reference), let .freeResponse(reference):
            texts.append(reference)
        case let .recognition(image, _):
            // The image's own text is not listed: the learner is meant to read
            // it off the picture, and offering it as selectable text alongside
            // would answer the question.
            texts.append(image.question ?? "")
        case .cloze, .digitEntry:
            break
        }
        return texts.filter { !$0.isEmpty }
    }

    /// How many things the learner actually answers. A set of five counts as
    /// five: it is what the lesson costs in time and attention.
    public var itemCount: Int {
        if case let .set(items) = content { return items.count }
        return 1
    }
}

// MARK: - Flat JSON ⇄ sum type

extension Exercise {
    private enum CodingKeys: String, CodingKey {
        case id, kind, skill, prompt, instruction, explanation, audioText
        case passage, reviewItemIds
        case options, correctIndex, acceptedAnswers, tokens, correctOrder, pairs
        case front, back, referenceAnswer, items, image
    }

    private enum Kind: String, Codable {
        case multipleChoice, cloze, reorder, matching, digitEntry, flashcard
        case translation, freeResponse, set, recognition
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        skill = try c.decode(Skill.self, forKey: .skill)
        prompt = try c.decode(String.self, forKey: .prompt)
        instruction = try c.decodeIfPresent(String.self, forKey: .instruction)
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation)
        audioText = try c.decodeIfPresent(String.self, forKey: .audioText)
        passage = try c.decodeIfPresent(String.self, forKey: .passage)
        reviewItemIds = try c.decodeIfPresent([String].self, forKey: .reviewItemIds) ?? []

        let kind = try c.decode(Kind.self, forKey: .kind)

        // A generated exercise whose kind-specific fields are missing is not
        // something to paper over -- it would render as an unanswerable card.
        // Fail loudly here, at the boundary, so ClaudeClient can retry.
        let path = c.codingPath
        let exerciseID = id
        func require<T>(_ value: T?, _ field: String) throws -> T {
            guard let value else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: path,
                    debugDescription: "exercise '\(exerciseID)' of kind '\(kind.rawValue)' is missing '\(field)'"
                ))
            }
            return value
        }

        /// Drops blank entries a generator padded a list with.
        ///
        /// Decoding is the ARCHIVE boundary, and an archive must be able to read
        /// back everything it ever wrote -- rejecting here would make a lesson
        /// the learner has already half-answered permanently unopenable. A blank
        /// entry carries no information, so dropping it loses nothing.
        ///
        /// Rejection belongs at the GENERATION boundary instead, where a retry
        /// is free and the model can be asked again: see `Lesson.validate()`.
        func dropBlanks(_ strings: [String]) -> [String] {
            strings.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        _ = path
        _ = exerciseID

        switch kind {
        case .multipleChoice:
            let rawOptions = try require(try c.decodeIfPresent([String].self, forKey: .options), "options")
            let options = dropBlanks(rawOptions)
            let index = try require(try c.decodeIfPresent(Int.self, forKey: .correctIndex), "correctIndex")
            guard options.indices.contains(index) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: c.codingPath,
                    debugDescription: "exercise '\(id)': correctIndex \(index) is out of range for \(options.count) options"
                ))
            }
            content = .multipleChoice(options: options, correctIndex: index)

        case .cloze:
            let accepted = try require(
                try c.decodeIfPresent([String].self, forKey: .acceptedAnswers), "acceptedAnswers")
            content = .cloze(accepted: dropBlanks(accepted))

        case .digitEntry:
            let accepted = try require(
                try c.decodeIfPresent([String].self, forKey: .acceptedAnswers), "acceptedAnswers")
            content = .digitEntry(accepted: dropBlanks(accepted))

        case .reorder:
            let tokens = try require(try c.decodeIfPresent([String].self, forKey: .tokens), "tokens")

            let order = try require(try c.decodeIfPresent([Int].self, forKey: .correctOrder), "correctOrder")
            guard Set(order) == Set(tokens.indices) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: c.codingPath,
                    debugDescription: "exercise '\(id)': correctOrder must be a permutation of token indices"
                ))
            }
            content = .reorder(tokens: tokens, correctOrder: order)

        case .matching:
            let rawPairs = try require(try c.decodeIfPresent([Pair].self, forKey: .pairs), "pairs")
            let pairs = rawPairs.filter {
                !$0.left.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.right.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard pairs.count >= 2 else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: c.codingPath,
                    debugDescription: "exercise '\(id)': matching needs at least 2 pairs"
                ))
            }
            content = .matching(pairs: pairs)

        case .flashcard:
            content = .flashcard(
                front: try require(try c.decodeIfPresent(String.self, forKey: .front), "front"),
                back: try require(try c.decodeIfPresent(String.self, forKey: .back), "back"))

        case .translation:
            content = .translation(reference: try require(
                try c.decodeIfPresent(String.self, forKey: .referenceAnswer), "referenceAnswer"))

        case .freeResponse:
            content = .freeResponse(reference: try require(
                try c.decodeIfPresent(String.self, forKey: .referenceAnswer), "referenceAnswer"))

        case .recognition:
            let image = try require(
                try c.decodeIfPresent(ImageSpec.self, forKey: .image), "image")
            let accepted = dropBlanks(try require(
                try c.decodeIfPresent([String].self, forKey: .acceptedAnswers),
                "acceptedAnswers"))
            guard !image.targets.isEmpty, !accepted.isEmpty else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: path,
                    debugDescription: "exercise '\(exerciseID)': a recognition exercise needs both image targets and accepted answers"
                ))
            }
            content = .recognition(image: image, accepted: accepted)

        case .set:
            let raw = try require(
                try c.decodeIfPresent([SetItem].self, forKey: .items), "items")
            let items = raw.filter {
                !$0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !dropBlanks($0.acceptedAnswers).isEmpty
            }
            guard items.count >= 2 else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: path,
                    debugDescription: "exercise '\(exerciseID)': a set needs at least 2 usable items"
                ))
            }
            content = .set(items: items)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(skill, forKey: .skill)
        try c.encode(prompt, forKey: .prompt)
        try c.encodeIfPresent(instruction, forKey: .instruction)
        try c.encodeIfPresent(explanation, forKey: .explanation)
        try c.encodeIfPresent(audioText, forKey: .audioText)
        try c.encodeIfPresent(passage, forKey: .passage)
        try c.encode(reviewItemIds, forKey: .reviewItemIds)

        switch content {
        case let .multipleChoice(options, correctIndex):
            try c.encode(Kind.multipleChoice, forKey: .kind)
            try c.encode(options, forKey: .options)
            try c.encode(correctIndex, forKey: .correctIndex)
        case let .cloze(accepted):
            try c.encode(Kind.cloze, forKey: .kind)
            try c.encode(accepted, forKey: .acceptedAnswers)
        case let .digitEntry(accepted):
            try c.encode(Kind.digitEntry, forKey: .kind)
            try c.encode(accepted, forKey: .acceptedAnswers)
        case let .reorder(tokens, correctOrder):
            try c.encode(Kind.reorder, forKey: .kind)
            try c.encode(tokens, forKey: .tokens)
            try c.encode(correctOrder, forKey: .correctOrder)
        case let .matching(pairs):
            try c.encode(Kind.matching, forKey: .kind)
            try c.encode(pairs, forKey: .pairs)
        case let .flashcard(front, back):
            try c.encode(Kind.flashcard, forKey: .kind)
            try c.encode(front, forKey: .front)
            try c.encode(back, forKey: .back)
        case let .translation(reference):
            try c.encode(Kind.translation, forKey: .kind)
            try c.encode(reference, forKey: .referenceAnswer)
        case let .freeResponse(reference):
            try c.encode(Kind.freeResponse, forKey: .kind)
            try c.encode(reference, forKey: .referenceAnswer)
        case let .set(items):
            try c.encode(Kind.set, forKey: .kind)
            try c.encode(items, forKey: .items)
        case let .recognition(image, accepted):
            try c.encode(Kind.recognition, forKey: .kind)
            try c.encode(image, forKey: .image)
            try c.encode(accepted, forKey: .acceptedAnswers)
        }
    }
}

// MARK: - Generation-time validation

extension Lesson {
    /// Problems that make a freshly generated lesson not worth showing.
    ///
    /// Separate from decoding on purpose. Decoding serves the archive, which
    /// must read back anything it wrote; this serves generation, where the only
    /// cost of being strict is asking the model again. A lesson that fails here
    /// is retried, not repaired.
    public enum Defect: Equatable, Sendable, CustomStringConvertible {
        case noExercises
        case blankPadding(exerciseID: String, field: String)
        case tooFewOptions(exerciseID: String)
        case silentListening(exerciseID: String)
        case leakedAnswer(exerciseID: String)
        case missingInstruction(exerciseID: String)
        case transcriptInPrompt(exerciseID: String)

        public var description: String {
            switch self {
            case .noExercises:
                "the lesson has no exercises"
            case let .blankPadding(id, field):
                "exercise '\(id)' padded '\(field)' with blank entries"
            case let .tooFewOptions(id):
                "exercise '\(id)' has fewer than two options to choose between"
            case let .silentListening(id):
                "listening exercise '\(id)' has no audioText, so there is nothing to hear"
            case let .leakedAnswer(id):
                "exercise '\(id)' gives its own answer away in the prompt"
            case let .missingInstruction(id):
                "exercise '\(id)' asks for a gap to be filled without saying what to type"
            case let .transcriptInPrompt(id):
                "listening exercise '\(id)' prints what is spoken, so there is nothing to listen for"
            }
        }

        /// Which exercise is at fault, when one is.
        ///
        /// A defective exercise is a local problem: the other seven in the lesson
        /// are fine, and throwing the whole generation away costs a full
        /// regeneration to fix one bad question.
        public var exerciseID: String? {
            switch self {
            case .noExercises: nil
            case let .blankPadding(id, _): id
            case let .tooFewOptions(id), let .silentListening(id), let .leakedAnswer(id),
                 let .missingInstruction(id), let .transcriptInPrompt(id): id
            }
        }
    }

    /// Checks a generated lesson. Empty means usable.
    public func validate(raw: [String: Any]? = nil) -> [Defect] {
        var defects: [Defect] = []
        if exercises.isEmpty { defects.append(.noExercises) }

        for exercise in exercises {
            switch exercise.content {
            case let .multipleChoice(options, correctIndex):
                if options.count < 2 {
                    defects.append(.tooFewOptions(exerciseID: exercise.id))
                }
                // An option reproduced verbatim in the prompt is a giveaway.
                if options.indices.contains(correctIndex),
                   options[correctIndex].count > 3,
                   Furigana.stripped(exercise.prompt)
                       .contains(Furigana.stripped(options[correctIndex])) {
                    defects.append(.leakedAnswer(exerciseID: exercise.id))
                }
            case let .matching(pairs):
                if pairs.count < 2 {
                    defects.append(.blankPadding(exerciseID: exercise.id, field: "pairs"))
                }
            case let .cloze(accepted), let .digitEntry(accepted):
                if accepted.isEmpty {
                    defects.append(.blankPadding(
                        exerciseID: exercise.id, field: "acceptedAnswers"))
                }
                // A cloze whose answer is already printed in the prompt tests
                // nothing.
                if let answer = accepted.first, answer.count > 2,
                   Furigana.stripped(exercise.prompt).contains(answer) {
                    defects.append(.leakedAnswer(exerciseID: exercise.id))
                }
            case let .reorder(tokens, _):
                if tokens.count < 2 {
                    defects.append(.blankPadding(exerciseID: exercise.id, field: "tokens"))
                }
            case let .recognition(image, accepted):
                if image.targets.isEmpty || accepted.isEmpty {
                    defects.append(.blankPadding(
                        exerciseID: exercise.id, field: "recognition"))
                }
                // The answer must be among what the picture will show,
                // otherwise the learner is asked to read something that was
                // never drawn.
                let shown = image.targets.map(Furigana.stripped)
                if !accepted.isEmpty, !shown.isEmpty,
                   !accepted.contains(where: { answer in
                       shown.contains { $0.contains(Furigana.stripped(answer)) }
                   }) {
                    defects.append(.leakedAnswer(exerciseID: exercise.id))
                }
            case let .set(items):
                if items.count < 2 {
                    defects.append(.blankPadding(exerciseID: exercise.id, field: "items"))
                }
                for item in items where item.acceptedAnswers.isEmpty {
                    defects.append(.blankPadding(
                        exerciseID: exercise.id, field: "items.acceptedAnswers"))
                }
            default:
                break
            }

            if exercise.skill == .listening,
               (exercise.audioText ?? "").isEmpty {
                defects.append(.silentListening(exerciseID: exercise.id))
            }

            // A listening exercise that writes the spoken line into its own
            // prompt is a reading exercise wearing a costume: the learner can
            // answer without ever pressing play.
            if let audio = exercise.audioText, !audio.isEmpty {
                let spoken = Furigana.stripped(audio)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "「」。、 \n"))
                if spoken.count >= 4,
                   Furigana.stripped(exercise.prompt).contains(spoken) {
                    defects.append(.transcriptInPrompt(exerciseID: exercise.id))
                }
            }

            // A gap with no instruction is ambiguous: fragment, or whole
            // sentence? The learner reads that ambiguity as the app misbehaving.
            if case .cloze = exercise.content,
               (exercise.instruction ?? "").trimmingCharacters(
                   in: .whitespacesAndNewlines).isEmpty {
                defects.append(.missingInstruction(exerciseID: exercise.id))
            }
        }
        return defects
    }
}
