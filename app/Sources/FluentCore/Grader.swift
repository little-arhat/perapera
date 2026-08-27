import Foundation

/// What the learner submitted for one exercise.
public enum Answer: Codable, Sendable, Equatable {
    case choice(Int)
    case text(String)
    case order([Int])
    case matches([Int])          // matches[i] = index of the right-hand item chosen for pair i
    case selfRated(Int)          // 0-5, flashcards only
    case texts([String])         // one per item, sets only
    case skipped
}

/// The result of grading one exercise. `nil` from the grader means "the teacher
/// must decide this one" -- absence of a verdict, not a failing verdict.
public struct Verdict: Codable, Sendable, Equatable {
    public let isCorrect: Bool
    /// 0-10, matching the scale the teacher uses so both feed SM-2 identically.
    public let score: Int
    /// What the learner should have written, for display after answering.
    public let correctVersion: String

    public init(isCorrect: Bool, score: Int, correctVersion: String) {
        self.isCorrect = isCorrect
        self.score = score
        self.correctVersion = correctVersion
    }

    /// SM-2 quality, on the 0-5 scale `update-db.py` expects.
    public var quality: Int { min(5, max(0, score / 2)) }
}

/// The outcome of grading one answer.
///
/// Three outcomes, not two. A grader that must answer yes/no about text it
/// cannot fully judge will be wrong in the expensive direction: telling a
/// learner their correct Japanese is wrong teaches them to distrust the app.
/// So an answer that is close but not identical is handed to the teacher
/// instead of guessed at.
public enum Grading: Sendable {
    /// Decided on the spot. This is the common case and the one that makes
    /// offline practice worth doing.
    case decided(Verdict)
    /// Needs judgement at the end of the lesson.
    case needsTeacher(Reason)

    public enum Reason: Sendable, Equatable {
        /// Open-ended by nature: a translation or a written answer.
        case byDesign
        /// Close to an accepted answer, but not equal to it. Might be a correct
        /// variant the generator did not list, might be a near miss -- either
        /// way, not the app's call.
        case closeCall
    }

    public var verdict: Verdict? {
        if case let .decided(verdict) = self { return verdict }
        return nil
    }
}

/// Grades the exercise kinds that can be decided without a teacher.
///
/// Pure: no I/O, no clock, no randomness. Everything here is a function of its
/// arguments, which is what makes offline practice trustworthy -- the verdict a
/// learner sees on a plane is the same one the teacher would have given.
public enum Grader {
    /// Kept for call sites that only care about a decided verdict.
    public static func grade(_ exercise: Exercise, _ answer: Answer) -> Verdict? {
        outcome(exercise, answer).verdict
    }

    public static func outcome(_ exercise: Exercise, _ answer: Answer) -> Grading {
        switch exercise.content {
        case let .multipleChoice(options, correctIndex):
            let correctText = options[correctIndex]
            guard case let .choice(picked) = answer else {
                return .decided(Verdict(isCorrect: false, score: 0, correctVersion: correctText))
            }
            let ok = picked == correctIndex
            return .decided(Verdict(isCorrect: ok, score: ok ? 10 : 0, correctVersion: correctText))

        case let .cloze(accepted):
            return gradeText(accepted: accepted, answer: answer,
                             prompt: exercise.prompt, allowDeferral: true)

        case let .digitEntry(accepted):
            // Digits are exact or wrong; there is no "close" reading of 2600.
            return gradeText(accepted: accepted, answer: answer,
                             prompt: exercise.prompt, allowDeferral: false)

        case let .reorder(tokens, correctOrder):
            let canonical = join(correctOrder.map { tokens[$0] })
            guard case let .order(submitted) = answer else {
                return .decided(Verdict(isCorrect: false, score: 0, correctVersion: canonical))
            }
            // Compare rendered strings, not index sequences: with duplicate
            // tokens ("を" twice) a different permutation can spell the same
            // correct sentence, and the learner is right.
            let ok = submitted.count == correctOrder.count
                && submitted.allSatisfy(tokens.indices.contains)
                && submitted.map { tokens[$0] } == correctOrder.map { tokens[$0] }
            return .decided(Verdict(isCorrect: ok, score: ok ? 10 : 0, correctVersion: canonical))

        case let .matching(pairs):
            let canonical = pairs.map { "\($0.left) = \($0.right)" }.joined(separator: " · ")
            guard case let .matches(chosen) = answer, chosen.count == pairs.count else {
                return .decided(Verdict(isCorrect: false, score: 0, correctVersion: canonical))
            }
            // Partial credit: matching is several judgements in one exercise, so
            // scoring it all-or-nothing would throw away most of the signal.
            // Compare the chosen right-hand *text*, not its index, so duplicate
            // right-hand values (two words sharing a gloss) both count.
            var correct = 0
            for i in pairs.indices {
                let pick = chosen[i]
                if pairs.indices.contains(pick), pairs[pick].right == pairs[i].right {
                    correct += 1
                }
            }
            let score = Int((Double(correct) / Double(pairs.count) * 10).rounded())
            return .decided(Verdict(isCorrect: correct == pairs.count, score: score,
                                    correctVersion: canonical))

        case let .flashcard(_, back):
            guard case let .selfRated(rating) = answer else {
                return .decided(Verdict(isCorrect: false, score: 0, correctVersion: back))
            }
            let clamped = min(5, max(0, rating))
            return .decided(Verdict(isCorrect: clamped >= 3, score: clamped * 2,
                                    correctVersion: back))

        case let .set(items):
            return gradeSet(items, answer)

        case .translation, .freeResponse:
            return .needsTeacher(.byDesign)
        }
    }

    /// Joins reordered tokens for display.
    ///
    /// Scripts that don't use inter-word spacing must not get them: rendering
    /// "京都 までの 切符" teaches the learner a spacing convention Japanese does
    /// not have. Decided from the text rather than from a configured language,
    /// so it stays correct for a learner studying two languages at once.
    public static func join(_ tokens: [String]) -> String {
        tokens.joined(separator: tokens.contains(where: usesUnspacedScript) ? "" : " ")
    }

    /// True for scripts written without spaces between words: Han, Hiragana,
    /// Katakana, Thai, Lao, Khmer, Burmese.
    private static func usesUnspacedScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF,   // Hiragana, Katakana
                 0x4E00...0x9FFF,   // CJK Unified Ideographs
                 0x3400...0x4DBF,   // CJK Extension A
                 0xF900...0xFAFF,   // CJK Compatibility Ideographs
                 0xFF66...0xFF9F,   // Half-width katakana
                 0x0E00...0x0E7F,   // Thai
                 0x0E80...0x0EFF,   // Lao
                 0x1780...0x17FF,   // Khmer
                 0x1000...0x109F:   // Burmese
                true
            default:
                false
            }
        }
    }

    /// Normalizes answers so a correct response is not rejected on a technicality.
    ///
    /// Deliberately narrow. It folds away differences that carry no meaning --
    /// surrounding and internal whitespace, full-width forms, case, and the
    /// trailing sentence punctuation Japanese and English disagree about. It does
    /// NOT fold away kana/kanji differences or vowel length: いくろ must stay
    /// wrong, or the app teaches the learner nothing.
    public static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Full-width → half-width (folds ２ to 2, Ａ to A), then case.
        t = t.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? t
        t = t.lowercased()
        t = t.filter { !$0.isWhitespace }
        // Unicode-aware rather than a hand-written character list: width folding
        // maps 。to ｡ and ！to !, so any fixed list is one transform away from
        // being wrong.
        while let last = t.last, last.isPunctuation {
            t.removeLast()
        }
        return t
    }
}

// MARK: - Text answers

extension Grader {
    /// Grades a typed answer against a list of accepted spellings.
    ///
    /// Three ways to be right, then one way to be unsure:
    ///
    /// 1. The answer matches an accepted spelling.
    /// 2. The answer is the whole sentence with the blank filled in. A learner
    ///    who writes はがきを3枚ください for 「はがき＿＿ください。」 has answered
    ///    correctly and more completely than asked; failing them would punish
    ///    correct Japanese on a formatting technicality.
    /// 3. The answer differs only in ways that carry no meaning (handled by
    ///    `normalize`).
    ///
    /// Anything close but not equal is handed to the teacher rather than
    /// guessed at — it may be a correct variant the generator never listed.
    static func gradeText(
        accepted: [String], answer: Answer, prompt: String, allowDeferral: Bool
    ) -> Grading {
        let canonical = accepted.first ?? ""
        guard case let .text(raw) = answer,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // A blank or skipped answer is decided, not ambiguous.
            return .decided(Verdict(isCorrect: false, score: 0, correctVersion: canonical))
        }

        let given = normalize(raw)
        if accepted.contains(where: { normalize($0) == given }) {
            return .decided(Verdict(isCorrect: true, score: 10, correctVersion: canonical))
        }
        if filledInVariants(prompt: prompt, accepted: accepted)
            .contains(where: { normalize($0) == given }) {
            return .decided(Verdict(isCorrect: true, score: 10, correctVersion: canonical))
        }

        if allowDeferral,
           accepted.contains(where: { isCloseTo(normalize($0), given) }) {
            return .needsTeacher(.closeCall)
        }
        return .decided(Verdict(isCorrect: false, score: 0, correctVersion: canonical))
    }

    /// The prompt's blank-bearing sentence, with the blank filled by each
    /// accepted answer.
    ///
    /// Returns nothing when there is no single blank to fill, which keeps the
    /// rule from firing on prompts it cannot reason about.
    static func filledInVariants(prompt: String, accepted: [String]) -> [String] {
        let plain = Furigana.stripped(prompt)
        guard let blank = blankRange(in: plain) else { return [] }

        let sentence = sentenceRange(around: blank, in: plain)
        let before = String(plain[sentence.lowerBound..<blank.lowerBound])
        let after = String(plain[blank.upperBound..<sentence.upperBound])
        return accepted.map { before + Furigana.stripped($0) + after }
    }

    /// The run of underscore characters a generator uses to mark a gap.
    private static func blankRange(in text: String) -> Range<String.Index>? {
        let markers: Set<Character> = ["＿", "_", "―", "─"]
        guard let start = text.firstIndex(where: markers.contains) else { return nil }
        var end = start
        while end < text.endIndex, markers.contains(text[end]) {
            end = text.index(after: end)
        }
        // A second, separate blank means the prompt wants two answers; filling
        // one of them would produce a sentence the learner never claimed.
        let rest = text[end...]
        if rest.contains(where: markers.contains) { return nil }
        return start..<end
    }

    /// The span around the blank that reads as one sentence: bounded by Japanese
    /// quotation marks where present, otherwise by sentence-ending punctuation
    /// or a line break.
    private static func sentenceRange(
        around blank: Range<String.Index>, in text: String
    ) -> Range<String.Index> {
        let openers: Set<Character> = ["「", "『", "（", "(", "\u{201C}"]
        let closers: Set<Character> = ["」", "』", "）", ")", "\u{201D}"]
        let stops: Set<Character> = ["。", ".", "!", "?", "！", "？", "\n"]

        var start = blank.lowerBound
        while start > text.startIndex {
            let previous = text.index(before: start)
            let character = text[previous]
            if openers.contains(character) || stops.contains(character) { break }
            start = previous
        }

        var end = blank.upperBound
        while end < text.endIndex {
            let character = text[end]
            if closers.contains(character) { break }
            if stops.contains(character) {
                // Keep the terminator: `normalize` strips it anyway, and
                // including it avoids cutting 。off mid-comparison.
                end = text.index(after: end)
                break
            }
            end = text.index(after: end)
        }
        return start..<end
    }

    /// Whether two normalized answers are near enough that the app should not
    /// rule on them alone.
    ///
    /// Deliberately narrow, because deferring costs the learner the instant
    /// feedback that makes offline practice worth doing:
    ///
    /// - **Containment** defers: they wrote more or less than asked, which may
    ///   well be right.
    /// - **A single-character difference** defers: probably a typo.
    /// - **A reordering never defers.** Same characters in a different order is
    ///   a word-order error, and word order is exactly what these exercises
    ///   teach. 切符二枚をください is a known mistake, not an ambiguity, and the
    ///   learner deserves to be told so at once.
    static func isCloseTo(_ expected: String, _ given: String) -> Bool {
        guard !expected.isEmpty, !given.isEmpty, expected != given else { return false }
        if isReordering(expected, given) { return false }
        if expected.contains(given) || given.contains(expected) { return true }
        // A one-character difference is a typo only when the answer is long
        // enough for typos to happen. On a short answer it is the whole answer:
        // が for を is not a slip, it is the mistake the exercise is testing,
        // and the learner should be told so immediately.
        guard expected.count >= 4 else { return false }
        return editDistance(Array(expected), Array(given), limit: 1) <= 1
    }

    /// Same characters, different arrangement.
    private static func isReordering(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        return a.sorted() == b.sorted()
    }

    /// Levenshtein distance, abandoned once it exceeds `limit`.
    static func editDistance(
        _ a: [Character], _ b: [Character], limit: Int
    ) -> Int {
        if abs(a.count - b.count) > limit { return limit + 1 }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...max(1, a.count) where !a.isEmpty {
            current[0] = i
            var rowBest = current[0]
            for j in 1...max(1, b.count) where !b.isEmpty {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1]
                    : min(previous[j - 1], previous[j], current[j - 1]) + 1
                rowBest = min(rowBest, current[j])
            }
            if rowBest > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}


// MARK: - Sets

extension Grader {
    /// Grades a drill item by item.
    ///
    /// Partial credit, because a set is several judgements: scoring eight gaps
    /// as one pass/fail throws away almost all the signal, and SM-2 needs the
    /// signal. If any single item is a close call the whole set goes to the
    /// teacher -- one ambiguous gap should not be silently marked wrong just
    /// because the other seven were clear.
    static func gradeSet(_ items: [Exercise.SetItem], _ answer: Answer) -> Grading {
        let canonical = items.enumerated()
            .map { "\($0.offset + 1). \($0.element.acceptedAnswers.first ?? "")" }
            .joined(separator: "   ")

        guard case let .texts(given) = answer, given.count == items.count else {
            return .decided(Verdict(isCorrect: false, score: 0, correctVersion: canonical))
        }

        var correct = 0
        var deferred = false
        for (item, typed) in zip(items, given) {
            switch gradeText(accepted: item.acceptedAnswers, answer: .text(typed),
                             prompt: item.prompt, allowDeferral: true) {
            case let .decided(verdict):
                if verdict.isCorrect { correct += 1 }
            case .needsTeacher:
                deferred = true
            }
        }
        if deferred { return .needsTeacher(.closeCall) }

        let score = Int((Double(correct) / Double(items.count) * 10).rounded())
        return .decided(Verdict(isCorrect: correct == items.count, score: score,
                                correctVersion: canonical))
    }

    /// Per-item verdicts, for showing which gaps were right.
    public static func setVerdicts(
        _ items: [Exercise.SetItem], _ answer: Answer
    ) -> [Bool?] {
        guard case let .texts(given) = answer, given.count == items.count else {
            return Array(repeating: nil, count: items.count)
        }
        return zip(items, given).map { item, typed in
            switch gradeText(accepted: item.acceptedAnswers, answer: .text(typed),
                             prompt: item.prompt, allowDeferral: true) {
            case let .decided(verdict): verdict.isCorrect
            case .needsTeacher: nil
            }
        }
    }
}
