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
