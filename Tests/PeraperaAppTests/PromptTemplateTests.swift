import Foundation
import Testing
@testable import PeraperaApp

// A prompt is the one input to the model that nothing downstream validates. A
// lesson built from a half-filled template comes back looking exactly like a
// good one -- which is how the teacher's brief stayed unread for weeks while
// every lesson looked fine.

@Test func fillsEveryPlaceholder() throws {
    let filled = try ResourceLoader.fill(
        "Hello {{NAME}}, you are {{LEVEL}}.",
        with: ["NAME": "Roma", "LEVEL": "A1"], named: "t")
    #expect(filled == "Hello Roma, you are A1.")
}

@Test func refusesAPlaceholderNobodyFilled() {
    #expect(throws: ResourceLoader.TemplateError.self) {
        try ResourceLoader.fill(
            "Hello {{NAME}}. {{TEACHER_PLAN}}", with: ["NAME": "Roma"], named: "t")
    }
}

@Test func refusesAValueWithNowhereToGo() {
    // The other half of the same bug: context assembled at cost, then dropped
    // on the floor because the template no longer mentions it.
    #expect(throws: ResourceLoader.TemplateError.self) {
        try ResourceLoader.fill(
            "Hello {{NAME}}.", with: ["NAME": "Roma", "TEACHER_PLAN": "drill を"],
            named: "t")
    }
}

@Test func theErrorNamesWhatIsMissing() throws {
    let error = ResourceLoader.TemplateError.mismatched(
        template: "Prompts/generate-lesson.md",
        unfilled: ["TEACHER_PLAN"], unused: ["LEGACY"])
    let text = try #require(error.errorDescription)
    #expect(text.contains("Prompts/generate-lesson.md"))
    #expect(text.contains("{{TEACHER_PLAN}}"))
    #expect(text.contains("LEGACY"))
}

@Test func oneOccurrenceIsAsGoodAsFive() throws {
    let filled = try ResourceLoader.fill(
        "{{N}} items, {{N}} per set, {{N}} minutes.", with: ["N": "5"], named: "t")
    #expect(filled == "5 items, 5 per set, 5 minutes.")
}

@Test func aValueIsNeverItselfATemplate() throws {
    // Learner text is substituted in, and braces in it are text. Substituting
    // into an already-substituted value would make the result depend on the
    // order a dictionary iterates in, which is no order at all.
    let filled = try ResourceLoader.fill(
        "{{NOTES}} / {{NAME}}",
        with: ["NOTES": "wrote {{NAME}} on the form", "NAME": "Roma"], named: "t")
    #expect(filled == "wrote {{NAME}} on the form / Roma")
}

@Test func lowercaseBracesAreNotPlaceholders() throws {
    // Prompts show the learner's own notation, e.g. a gap marked {{...}} by a
    // textbook. Only SHOUTING_SNAKE names are ours.
    let filled = try ResourceLoader.fill(
        "Fill the gap {{kanji}} with {{WORD}}.", with: ["WORD": "駅"], named: "t")
    #expect(filled == "Fill the gap {{kanji}} with 駅.")
}

// MARK: - What the shipped prompts still ask for

// The loop these guard is quiet when it breaks: drop the tag from the schema
// and lessons still generate, still grade and still record — only the counts
// per point stop growing, which nothing fails over.

@Test func theSchemaStillAsksEachExerciseToNameItsPoint() throws {
    let schema = try ResourceLoader().text("Schemas/lesson.schema.json")
    let json = try JSONSerialization.jsonObject(with: Data(schema.utf8)) as! [String: Any]
    let exercises = (json["properties"] as! [String: Any])["exercises"] as! [String: Any]
    let fields = ((exercises["items"] as! [String: Any])["properties"] as! [String: Any])
    let pattern = try #require(fields["pattern"] as? [String: Any])
    #expect(pattern["type"] as? String == "string")
    // snake_case is the shared namespace with mistakes-db's pattern_id.
    #expect(pattern["pattern"] as? String == "^[a-z0-9_]+$")
}

@Test func bothPromptsSpeakOfTheSameIds() throws {
    let generation = try ResourceLoader().text("Prompts/generate-lesson.md")
    #expect(generation.contains("{{PATTERN_MASTERY}}"))
    #expect(generation.contains("`pattern`"))

    // Grading files the errors; generation files the answers. If the grader is
    // not told which id a question is already filed under, it coins a synonym
    // and one point is tracked twice.
    let grading = try ResourceLoader().text("Prompts/grade-lesson.md")
    #expect(grading.contains("Point:"))
}
