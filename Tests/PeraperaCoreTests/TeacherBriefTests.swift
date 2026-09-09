import Testing
@testable import PeraperaCore

// The brief is the only thing the teacher knows. A document that silently fails
// to load changes how every lesson is taught with nothing in the output to say so.

@Test func briefKeepsDocumentOrderAndNamesEachSource() {
    let brief = TeacherBrief.assemble(
        preamble: "You are the teacher.",
        documents: [.init(name: "docs/METHODOLOGY.md", text: "Aim for 60-70% success."),
                    .init(name: "refs/feedback.md", text: "Say what was right first.")])
    #expect(brief.hasPrefix("You are the teacher."))
    #expect(brief.contains("docs/METHODOLOGY.md"))
    #expect(brief.range(of: "Aim for 60-70%")!.lowerBound
            < brief.range(of: "Say what was right first")!.lowerBound)
}

@Test func briefWithNoDocumentsIsJustThePreamble() {
    #expect(TeacherBrief.assemble(preamble: "Only this.", documents: []) == "Only this.")
}
