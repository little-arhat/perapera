import Testing
@testable import PeraperaCore

// The drill's value is that it asks about the character the learner cannot read,
// in a typeface they have not seen it in. Both halves have to be true.

@Test func everyGroupIsARealConfusionWithAStatedDifference() {
    for group in ScriptDrill.groups {
        #expect(group.characters.count >= 2, "\(group.id) needs something to confuse with")
        #expect(Set(group.characters).count == group.characters.count,
                "\(group.id) repeats a character")
        #expect(group.difference.count > 30,
                "\(group.id) must say what actually separates them")
    }
}

@Test func groupIdsAreUnique() {
    let ids = ScriptDrill.groups.map(\.id)
    #expect(Set(ids).count == ids.count)
}

@Test func aFreshLearnerIsAskedSomething() {
    let question = ScriptDrill.next(seen: [:], correct: [:], families: ["Klee"])
    #expect(question != nil)
    #expect(question?.family == "Klee")
    #expect(question.map { $0.options.contains($0.answer) } == true)
}

@Test func theWorstGroupComesFirst() {
    // シ/ツ answered badly, ソ/ン answered perfectly: ask about シ/ツ.
    let seen = ["シ": 10, "ツ": 10, "ソ": 10, "ン": 10]
    let correct = ["シ": 2, "ツ": 2, "ソ": 10, "ン": 10]
    let question = ScriptDrill.next(seen: seen, correct: correct, families: ["Klee"])
    #expect(question?.group.id == "shi-tsu")
}

@Test func withinAGroupTheWeakerCharacterIsAsked() {
    // Every group answered, シ/ツ the worst of them, and within it ツ the worse
    // of the two. Giving the others data matters: an unseen group scores 0.5 and
    // would otherwise win on having been seen less.
    var seen: [String: Int] = [:], correct: [String: Int] = [:]
    for group in ScriptDrill.groups {
        for character in group.characters { seen[character] = 10; correct[character] = 9 }
    }
    seen["シ"] = 10; correct["シ"] = 4
    seen["ツ"] = 10; correct["ツ"] = 1

    let question = ScriptDrill.next(seen: seen, correct: correct, families: ["Klee"])
    #expect(question?.group.id == "shi-tsu")
    #expect(question?.answer == "ツ")
}

@Test func aGroupAtFiftyPercentDoesNotOutrankUntouchedMaterial() {
    // An unseen group is treated as half-wrong, so it ties with a group actually
    // sitting at 50% — and the tie breaks toward the one seen less. Otherwise a
    // learner stuck at a coin-flip never meets anything new.
    let seen = ["シ": 10, "ツ": 10]
    let correct = ["シ": 5, "ツ": 5]
    let question = ScriptDrill.next(seen: seen, correct: correct, families: ["Klee"])
    #expect(question?.group.id != "shi-tsu")
}

@Test func unseenMaterialCompetesWithKnownWeakMaterial() {
    // Everything answered at 40% except one untouched group. The untouched one
    // scores 0.5, so the 40% group still wins — but an unseen group must beat a
    // group sitting at 60%, or new material never appears.
    var seen: [String: Int] = [:], correct: [String: Int] = [:]
    for group in ScriptDrill.groups.dropFirst() {
        for c in group.characters { seen[c] = 10; correct[c] = 6 }
    }
    let question = ScriptDrill.next(seen: seen, correct: correct, families: ["Klee"])
    #expect(question?.group.id == ScriptDrill.groups[0].id)
}

@Test func noFontsMeansNoQuestionRatherThanACrash() {
    #expect(ScriptDrill.next(seen: [:], correct: [:], families: []) == nil)
}

@Test func theFontIsChosenFromWhatIsAvailable() {
    let families = ["Klee", "Kaiti SC", "Yuppy SC"]
    let question = ScriptDrill.next(seen: [:], correct: [:], families: families,
                                    randomness: { _ in 2 })
    #expect(question?.family == "Yuppy SC")
}
