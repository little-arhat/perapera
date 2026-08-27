import Testing
import Foundation
@testable import FluentCore

// MARK: - Helpers

/// Builds an exercise the way the app really gets one: from generated JSON,
/// through the real decoder. Production code never constructs one any other way,
/// so neither do these tests.
private func decodeExercise(_ fields: [String: Any]) throws -> Exercise {
    var object: [String: Any] = ["id": "ex", "skill": "grammar", "prompt": "p"]
    object.merge(fields) { _, new in new }
    let data = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(Exercise.self, from: data)
}

private func exercise(_ fields: [String: Any]) -> Exercise {
    try! decodeExercise(fields)
}

// MARK: - Normalization
//
// The line this draws is the whole point: fold away what carries no meaning,
// keep every difference that does. A grader that is too generous teaches the
// learner that wrong answers are right.

@Test func normalizeFoldsWhitespaceAndPunctuation() {
    #expect(Grader.normalize(" きっぷ 　") == Grader.normalize("きっぷ"))
    #expect(Grader.normalize("これはいくらですか。") == Grader.normalize("これはいくらですか"))
    #expect(Grader.normalize("切符を 二枚 ください") == Grader.normalize("切符を二枚ください"))
}

@Test func normalizeFoldsFullWidthDigits() {
    #expect(Grader.normalize("２６００") == Grader.normalize("2600"))
}

@Test func normalizeKeepsMeaningfulDifferences() {
    // A vowel slip is a real mistake -- this is the いくろ/いくら case.
    #expect(Grader.normalize("いくろ") != Grader.normalize("いくら"))
    // Kana and kanji are different answers; acceptedAnswers lists both when both count.
    #expect(Grader.normalize("きっぷ") != Grader.normalize("切符"))
    // Gemination is the difference between はっせん and はちせん.
    #expect(Grader.normalize("はちせん") != Grader.normalize("はっせん"))
}

// MARK: - Multiple choice

@Test func multipleChoiceGradesPickedIndex() {
    let ex = exercise(["kind": "multipleChoice", "options": ["は", "を", "で"], "correctIndex": 2])
    #expect(Grader.grade(ex, .choice(2))?.isCorrect == true)
    #expect(Grader.grade(ex, .choice(0))?.isCorrect == false)
    #expect(Grader.grade(ex, .choice(2))?.correctVersion == "で")
}

@Test func skippedAnswerIsWrongNotCrash() {
    let ex = exercise(["kind": "multipleChoice", "options": ["は", "を"], "correctIndex": 0])
    let v = Grader.grade(ex, .skipped)
    #expect(v?.isCorrect == false)
    #expect(v?.score == 0)
}

// MARK: - Cloze / digit entry

@Test func clozeAcceptsAnyListedSpelling() {
    let ex = exercise(["kind": "cloze", "acceptedAnswers": ["切符を二枚ください", "切符を2枚ください", "きっぷを2まいください"]])
    for answer in ["切符を二枚ください", "切符を2枚ください", " きっぷを2まいください "] {
        #expect(Grader.grade(ex, .text(answer))?.isCorrect == true, "rejected: \(answer)")
    }
    #expect(Grader.grade(ex, .text("切符二枚をください"))?.isCorrect == false)
}

@Test func clozeCorrectVersionIsTheFirstAccepted() {
    let ex = exercise(["kind": "cloze", "acceptedAnswers": ["さんぜんはっぴゃくえん", "3800円"]])
    #expect(Grader.grade(ex, .text("nope"))?.correctVersion == "さんぜんはっぴゃくえん")
}

@Test func digitEntryFoldsWidthButNotValue() {
    let ex = exercise(["kind": "digitEntry", "acceptedAnswers": ["2600"]])
    #expect(Grader.grade(ex, .text("２６００"))?.isCorrect == true)
    #expect(Grader.grade(ex, .text("2060"))?.isCorrect == false)
}

// MARK: - Reorder

@Test func reorderAcceptsTheCorrectSequence() {
    // 明日 / 電車で / 東京に / 行きます -- tokens supplied out of order.
    let tokens = ["東京に", "明日", "行きます", "電車で"]
    let ex = exercise(["kind": "reorder", "tokens": tokens, "correctOrder": [1, 3, 0, 2]])
    #expect(Grader.grade(ex, .order([1, 3, 0, 2]))?.isCorrect == true)
    #expect(Grader.grade(ex, .order([1, 0, 3, 2]))?.isCorrect == false)
}

@Test func reorderAcceptsADifferentPermutationThatSpellsTheSameSentence() {
    // Duplicate tokens: two identical を. Picking the "other" を is still right.
    let tokens = ["を", "を", "水", "ください"]
    let ex = exercise(["kind": "reorder", "tokens": tokens, "correctOrder": [2, 0, 3, 1]])
    #expect(Grader.grade(ex, .order([2, 1, 3, 0]))?.isCorrect == true)
}

// MARK: - Matching

@Test func matchingGivesPartialCredit() {
    let pairs = [
        ["left": "はがき", "right": "枚"],
        ["left": "かさ", "right": "本"],
        ["left": "りんご", "right": "個"],
        ["left": "ねこ", "right": "匹"],
    ]
    let ex = exercise(["kind": "matching", "pairs": pairs])
    #expect(Grader.grade(ex, .matches([0, 1, 2, 3]))?.score == 10)
    #expect(Grader.grade(ex, .matches([0, 1, 3, 2]))?.score == 5)   // 2 of 4
    #expect(Grader.grade(ex, .matches([0, 1, 3, 2]))?.isCorrect == false)
    #expect(Grader.grade(ex, .matches([3, 2, 1, 0]))?.score == 0)
}

@Test func matchingWithDuplicateRightSidesCountsBothPicks() {
    // つ is the fallback counter for both -- either index is a right answer.
    let pairs = [
        ["left": "りんご", "right": "つ"],
        ["left": "みかん", "right": "つ"],
    ]
    let ex = exercise(["kind": "matching", "pairs": pairs])
    #expect(Grader.grade(ex, .matches([1, 0]))?.score == 10)
}

// MARK: - Flashcard

@Test func flashcardUsesSelfRatingAsQuality() {
    let ex = exercise(["kind": "flashcard", "front": "切符", "back": "きっぷ — ticket"])
    #expect(Grader.grade(ex, .selfRated(5))?.score == 10)
    #expect(Grader.grade(ex, .selfRated(0))?.isCorrect == false)
    #expect(Grader.grade(ex, .selfRated(3))?.isCorrect == true)
    // Out-of-range ratings clamp rather than producing an invalid quality.
    #expect(Grader.grade(ex, .selfRated(99))?.score == 10)
}

// MARK: - Teacher-graded kinds

@Test func teacherGradedKindsReturnNoVerdict() {
    #expect(Grader.grade(exercise(["kind": "translation", "referenceAnswer": "x"]), .text("y")) == nil)
    #expect(Grader.grade(exercise(["kind": "freeResponse", "referenceAnswer": "x"]), .text("y")) == nil)
}

// MARK: - SM-2 bridge

@Test func qualityIsHalfTheScoreClampedToFive() {
    #expect(Verdict(isCorrect: true, score: 10, correctVersion: "").quality == 5)
    #expect(Verdict(isCorrect: true, score: 9, correctVersion: "").quality == 4)
    #expect(Verdict(isCorrect: false, score: 5, correctVersion: "").quality == 2)
    #expect(Verdict(isCorrect: false, score: 0, correctVersion: "").quality == 0)
}

// MARK: - Token joining
//
// Rendering "京都 までの 切符" would teach a spacing convention Japanese does
// not have. The rule is decided from the text, not from a configured language.

@Test func joinOmitsSpacesForUnspacedScripts() {
    #expect(Grader.join(["京都", "までの", "切符", "を", "二枚", "ください"])
            == "京都までの切符を二枚ください")
    #expect(Grader.join(["はがき", "を", "三枚"]) == "はがきを三枚")
}

@Test func joinKeepsSpacesForSpacedScripts() {
    #expect(Grader.join(["ik", "ga", "naar", "huis"]) == "ik ga naar huis")
    #expect(Grader.join(["dos", "billetes", "por", "favor"]) == "dos billetes por favor")
}

@Test func reorderCorrectVersionRendersWithoutSpaces() {
    let tokens = ["切符", "京都", "二枚", "までの", "を", "ください"]
    let ex = exercise(["kind": "reorder", "tokens": tokens,
                       "correctOrder": [1, 3, 0, 4, 2, 5]])
    let verdict = Grader.grade(ex, .order([0, 1, 2, 3, 4, 5]))
    #expect(verdict?.correctVersion == "京都までの切符を二枚ください")
}

// MARK: - Blank padding
//
// Two boundaries, two obligations. Decoding serves the ARCHIVE, which must read
// back everything it wrote, so it drops meaningless blanks rather than making a
// half-answered lesson unopenable. Rejection lives at the GENERATION boundary
// (Lesson.validate), where a retry costs nothing.

@Test func decodingDropsBlankPairsRatherThanFailing() throws {
    let ex = try decodeExercise(["kind": "matching", "pairs": [
        ["left": "はがき", "right": "枚"],
        ["left": "かさ", "right": "本"],
        ["left": "", "right": ""],
    ]])
    guard case let .matching(pairs) = ex.content else {
        Issue.record("expected matching"); return
    }
    #expect(pairs.count == 2)
}

@Test func decodingDropsBlankAnswersAndOptions() throws {
    let cloze = try decodeExercise(["kind": "cloze", "acceptedAnswers": ["で", "", "  "]])
    guard case let .cloze(accepted) = cloze.content else {
        Issue.record("expected cloze"); return
    }
    #expect(accepted == ["で"])

    let choice = try decodeExercise(["kind": "multipleChoice",
                                     "options": ["は", "を", "  "], "correctIndex": 0])
    guard case let .multipleChoice(options, _) = choice.content else {
        Issue.record("expected multipleChoice"); return
    }
    #expect(options == ["は", "を"])
}

@Test func matchingWithTooFewRealPairsStillFails() {
    // Dropping blanks can leave nothing to match. That IS malformed.
    #expect(throws: (any Error).self) {
        try decodeExercise(["kind": "matching", "pairs": [
            ["left": "はがき", "right": "枚"],
            ["left": "", "right": ""],
        ]])
    }
}

// MARK: - Text answers: right, wrong, and not-my-call
//
// The expensive mistake is telling a learner their correct Japanese is wrong.
// So a cloze accepts the filled-in sentence as well as the fragment, and hands
// anything merely close to the teacher instead of ruling on it.

private let postcardPrompt = "郵便局[ゆうびんきょく]で。You want three postcards.「はがき＿＿＿ください。」"
private let postcardAnswers = ["を三枚", "を3枚", "をさんまい", "三枚", "3枚", "さんまい"]

private func clozeOutcome(_ typed: String) -> Grading {
    let ex = exercise(["kind": "cloze", "prompt": postcardPrompt,
                       "acceptedAnswers": postcardAnswers])
    return Grader.outcome(ex, .text(typed))
}

@Test func acceptsTheFragmentTheBlankAsksFor() {
    #expect(clozeOutcome("を三枚").verdict?.isCorrect == true)
    #expect(clozeOutcome("を3枚").verdict?.isCorrect == true)
    #expect(clozeOutcome("三枚").verdict?.isCorrect == true)
}

@Test func acceptsTheWholeSentenceWithTheBlankFilled() {
    // The case that prompted this: correct Japanese, fuller than asked for.
    #expect(clozeOutcome("はがきを3枚ください").verdict?.isCorrect == true)
    #expect(clozeOutcome("はがきを三枚ください。").verdict?.isCorrect == true)
    #expect(clozeOutcome("はがきをさんまいください").verdict?.isCorrect == true)
}

@Test func defersAnAnswerThatOverlapsAnAcceptedOne() {
    // Contains an accepted answer but adds material: may be right, may not.
    guard case .needsTeacher(.closeCall) = clozeOutcome("はがきを3枚") else {
        Issue.record("expected deferral, got \(clozeOutcome("はがきを3枚"))")
        return
    }
}

@Test func aReorderingIsDecidedWrongNotDeferred() {
    // を after the counter is THE mistake these exercises teach. Same
    // characters, different order -- an error, not an ambiguity, so the learner
    // is told at once rather than waiting for the teacher.
    let ex = exercise(["kind": "cloze", "prompt": "「切符＿＿ください」",
                       "acceptedAnswers": ["切符を二枚ください"]])
    let outcome = Grader.outcome(ex, .text("切符二枚をください"))
    #expect(outcome.verdict?.isCorrect == false)
    #expect(outcome.verdict != nil, "should be decided, not deferred")
}

@Test func decidesClearlyWrongAnswersImmediately() {
    // Instant feedback is most of the app's value; deferring everything
    // imperfect would erode it.
    #expect(clozeOutcome("を二本").verdict?.isCorrect == false)
    #expect(clozeOutcome("ぜんぜんちがう").verdict?.isCorrect == false)
    #expect(clozeOutcome("").verdict?.isCorrect == false)
}

@Test func digitEntryNeverDefers() {
    // There is no "close" reading of a price.
    let ex = exercise(["kind": "digitEntry", "prompt": "いくら？ ＿＿",
                       "acceptedAnswers": ["2600"]])
    #expect(Grader.outcome(ex, .text("2600")).verdict?.isCorrect == true)
    #expect(Grader.outcome(ex, .text("2601")).verdict?.isCorrect == false)
    #expect(Grader.outcome(ex, .text("2601")).verdict != nil)
}

@Test func fillsOnlyASingleUnambiguousBlank() {
    // Two blanks: filling one would build a sentence the learner never claimed.
    let two = Grader.filledInVariants(
        prompt: "「＿＿はがき＿＿ください」", accepted: ["を"])
    #expect(two.isEmpty)

    // No blank at all: nothing to expand.
    #expect(Grader.filledInVariants(prompt: "Say it in Japanese", accepted: ["はい"]).isEmpty)
}

@Test func expandsUsingTheQuotedSentenceOnly() {
    // The English scaffolding around the quote must not end up in the answer.
    let variants = Grader.filledInVariants(
        prompt: postcardPrompt, accepted: ["を三枚"])
    #expect(variants == ["はがきを三枚ください。"])
}

@Test func translationStillDefersByDesign() {
    let ex = exercise(["kind": "translation", "referenceAnswer": "x"])
    guard case .needsTeacher(.byDesign) = Grader.outcome(ex, .text("y")) else {
        Issue.record("expected byDesign deferral"); return
    }
}

// MARK: - Sets
//
// A drill is several judgements. Scoring eight gaps as one pass/fail throws
// away nearly all the signal SM-2 needs, so sets get partial credit.

private func drill() -> Exercise {
    exercise(["kind": "set", "prompt": "Particles", "instruction": "One particle each.",
              "items": [
                ["prompt": "コンビニ＿水を買います", "acceptedAnswers": ["で"]],
                ["prompt": "京都＿行きます", "acceptedAnswers": ["に", "へ"]],
                ["prompt": "はがき＿三枚ください", "acceptedAnswers": ["を"], "hint": "object"],
              ]])
}

@Test func setScoresEachItemForPartialCredit() {
    let ex = drill()
    #expect(Grader.outcome(ex, .texts(["で", "に", "を"])).verdict?.score == 10)
    #expect(Grader.outcome(ex, .texts(["で", "へ", "を"])).verdict?.score == 10)
    #expect(Grader.outcome(ex, .texts(["で", "に", "が"])).verdict?.score == 7)
    #expect(Grader.outcome(ex, .texts(["が", "が", "が"])).verdict?.score == 0)
}

@Test func setIsOnlyFullyCorrectWhenEveryItemIs() {
    #expect(Grader.outcome(drill(), .texts(["で", "に", "を"])).verdict?.isCorrect == true)
    #expect(Grader.outcome(drill(), .texts(["で", "に", "が"])).verdict?.isCorrect == false)
}

@Test func setReportsWhichItemsWereRight() {
    let verdicts = Grader.setVerdicts(
        {
            if case let .set(items) = drill().content { return items }
            return []
        }(), .texts(["で", "が", "を"]))
    #expect(verdicts == [true, false, true])
}

@Test func aWrongLengthAnswerIsNotACrash() {
    #expect(Grader.outcome(drill(), .texts(["で"])).verdict?.isCorrect == false)
    #expect(Grader.outcome(drill(), .skipped).verdict?.isCorrect == false)
}

@Test func setNeedsAtLeastTwoUsableItems() {
    #expect(throws: (any Error).self) {
        try decodeExercise(["kind": "set", "items": [
            ["prompt": "a", "acceptedAnswers": ["x"]],
            ["prompt": "", "acceptedAnswers": [""]],
        ]])
    }
}

@Test func lessonLengthCountsSetItems() throws {
    // A set of three is three things to answer, not one.
    #expect(drill().itemCount == 3)
    #expect(exercise(["kind": "cloze", "acceptedAnswers": ["で"]]).itemCount == 1)
}
