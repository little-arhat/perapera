import Testing
@testable import FluentCore

// The list answers "what should I work on?", so its ordering and its sense of
// partial progress are the whole feature — a topic half learned must not read
// the same as one untouched.

private func item(_ category: String, _ mastery: Int, due: Bool = false)
    -> (category: String, mastery: Int, isDue: Bool) {
    (category, mastery, due)
}

@Test func bandsItemsByMastery() {
    let topics = TopicBreakdown.from(items: [
        item("counters", 0), item("counters", 1), item("counters", 2),
        item("counters", 3), item("counters", 5),
    ])
    let counters = try! #require(topics.first)
    #expect(counters.new == 1)
    #expect(counters.learning == 2)
    #expect(counters.strong == 1)
    #expect(counters.mastered == 1)
    #expect(counters.total == 5)
}

@Test func leastCompleteComesFirst() {
    // The point of the list. The topic already at 80% is rarely the honest
    // answer to "what next?".
    let topics = TopicBreakdown.from(items: [
        item("nearly", 5), item("nearly", 5), item("nearly", 4),
        item("fresh", 0), item("fresh", 0), item("fresh", 0),
        item("middling", 2), item("middling", 3), item("middling", 1),
    ])
    #expect(topics.map(\.name) == ["fresh", "middling", "nearly"])
}

@Test func partialProgressCounts() {
    // All-or-nothing scoring would call both of these 0% and hide the
    // difference between "half learned" and "never seen".
    let halfLearned = TopicBreakdown.from(items: [
        item("a", 2), item("a", 2), item("a", 2), item("a", 2),
    ])[0]
    let untouched = TopicBreakdown.from(items: [
        item("b", 0), item("b", 0), item("b", 0), item("b", 0),
    ])[0]

    #expect(halfLearned.completion > untouched.completion)
    #expect(untouched.completion == 0)
    #expect(halfLearned.completion > 0)
}

@Test func aFinishedTopicReadsAsFinished() {
    let done = TopicBreakdown.from(items: [item("x", 5), item("x", 5)])[0]
    #expect(done.completion == 1.0)
    #expect(done.verdict == "done")

    let fresh = TopicBreakdown.from(items: [item("y", 0), item("y", 0)])[0]
    #expect(fresh.verdict == "barely started")
}

@Test func countsWhatIsDueNow() {
    let topics = TopicBreakdown.from(items: [
        item("counters", 1, due: true),
        item("counters", 2, due: true),
        item("counters", 3, due: false),
    ])
    #expect(topics[0].due == 2)
}

@Test func straySingleItemTagsAreNotTopics() {
    // A category with one item is how the data was filed, not a subject.
    let topics = TopicBreakdown.from(items: [
        item("real", 0), item("real", 1),
        item("stray", 0),
    ])
    #expect(topics.map(\.name) == ["real"])
}

@Test func categoryNamesAreMadeReadable() {
    #expect(TopicBreakdown.display("travel_station") == "travel station")
    #expect(TopicBreakdown.display("saved_kanji") == "kanji")
    #expect(TopicBreakdown.display("  ") == "")
}

@Test func emptyInputIsEmptyOutput() {
    #expect(TopicBreakdown.from(items: []).isEmpty)
}
