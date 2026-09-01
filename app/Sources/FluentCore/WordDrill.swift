import Foundation

/// A batch of words to translate, and the marking of them.
///
/// Pure: a drill is a value, so what counts as correct is decided without a UI
/// and can be tested. Grading reuses `Grader.gradeText`, so a word answered
/// acceptably here is answered acceptably in a lesson — two graders would drift
/// and the learner would be the one to discover it.
public struct WordDrill: Equatable, Sendable {
    public enum Direction: String, CaseIterable, Sendable {
        /// Shown the Japanese, type the meaning. Tests recognition.
        case toNative
        /// Shown the meaning, type the Japanese. Tests recall, which is harder
        /// and the direction that actually matters for speaking.
        case toTarget

        public var label: String {
            switch self {
            case .toNative: "JA → EN"
            case .toTarget: "EN → JA"
            }
        }
    }

    public struct Question: Equatable, Sendable, Identifiable {
        public let id: String
        /// What is shown.
        public let shown: String
        /// Readings shown only when the entry is kanji and furigana is on.
        public let reading: String?
        /// Every spelling that counts.
        public let accepted: [String]
        /// The word in use, revealed after answering rather than before.
        public let example: String?
        public let exampleGloss: String?

        public init(
            id: String, shown: String, reading: String?, accepted: [String],
            example: String?, exampleGloss: String?
        ) {
            self.id = id
            self.shown = shown
            self.reading = reading
            self.accepted = accepted
            self.example = example
            self.exampleGloss = exampleGloss
        }
    }

    public let direction: Direction
    public let questions: [Question]

    public init(direction: Direction, questions: [Question]) {
        self.direction = direction
        self.questions = questions
    }

    /// Builds a drill from saved words.
    ///
    /// Entries missing what the chosen direction needs are skipped rather than
    /// shown unanswerable — a word with no gloss cannot be translated into
    /// English, and asking anyway teaches nothing.
    public static func build(
        from items: [SavedItem], direction: Direction, limit: Int = 8
    ) -> WordDrill {
        let questions = items.compactMap { item -> Question? in
            let target = Furigana.stripped(item.content)
            let gloss = item.gloss.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty, !gloss.isEmpty else { return nil }

            switch direction {
            case .toNative:
                return Question(
                    id: item.id, shown: item.content, reading: item.reading,
                    accepted: [gloss], example: item.example,
                    exampleGloss: item.exampleGloss)
            case .toTarget:
                // Both the written form and the reading are accepted: typing
                // きっぷ for 切符 is knowing the word, and a kana keyboard is
                // the only one the app offers.
                var accepted = [target]
                if let reading = item.reading, !reading.isEmpty {
                    accepted.append(reading)
                }
                return Question(
                    id: item.id, shown: gloss, reading: nil,
                    accepted: accepted, example: item.example,
                    exampleGloss: item.exampleGloss)
            }
        }
        return WordDrill(direction: direction, questions: Array(questions.prefix(limit)))
    }

    /// Marks one answer. `nil` means the app declined to decide — the same
    /// three-outcome rule the lessons use.
    public func mark(_ question: Question, answer: String) -> Verdict? {
        Grader.gradeText(
            accepted: question.accepted,
            answer: .text(answer),
            prompt: "",
            // English glosses vary too much to rule on: "ticket" against "a
            // ticket" is not a mistake worth calling one, so a near miss is
            // shown rather than failed.
            allowDeferral: direction == .toNative
        ).verdict
    }
}
