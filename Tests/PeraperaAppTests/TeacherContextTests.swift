import Foundation
import Testing
@testable import PeraperaApp

// A fixture rather than the real Fluent: `swift test` on a clean checkout has no
// app bundle, so Locations.fluentRoot() is nil and a test resting on it would
// fail rather than skip.
private func fixture(withFeedbackTemplate: Bool = true) throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "fluent-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: root.appending(path: "docs"), withIntermediateDirectories: true)
    try "Aim for 60-70% success."
        .write(to: root.appending(path: "docs/METHODOLOGY.md"),
               atomically: true, encoding: .utf8)
    if withFeedbackTemplate {
        try fm.createDirectory(at: root.appending(path: ".claude/references"),
                               withIntermediateDirectories: true)
        try "Say what was right first."
            .write(to: root.appending(path: ".claude/references/feedback-template.md"),
                   atomically: true, encoding: .utf8)
    }
    return root
}

@Test func theBriefCarriesFluentsMethodology() throws {
    let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    let prompt = try TeacherContext.systemPrompt(fluentRoot: root, call: .generation)
    #expect(prompt.contains("Aim for 60-70% success."))
    #expect(prompt.contains("no tools"))
}

@Test func gradingIsBriefedMoreFullyThanGeneration() throws {
    let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    let generation = try TeacherContext.systemPrompt(fluentRoot: root, call: .generation)
    let grading = try TeacherContext.systemPrompt(fluentRoot: root, call: .grading)
    #expect(grading.count > generation.count)
    #expect(grading.contains("Say what was right first."))
    #expect(!generation.contains("Say what was right first."))
}

@Test func aMissingDocumentThrowsRatherThanShorteningTheBrief() throws {
    let root = try fixture(withFeedbackTemplate: false)
    defer { try? FileManager.default.removeItem(at: root) }
    // Generation does not need it; grading does, and must say so.
    #expect(throws: Never.self) {
        _ = try TeacherContext.systemPrompt(fluentRoot: root, call: .generation)
    }
    #expect(throws: TeacherContext.Failure.missing(".claude/references/feedback-template.md")) {
        _ = try TeacherContext.systemPrompt(fluentRoot: root, call: .grading)
    }
}

@Test func theBriefExcludesFluentsSessionChoreography() throws {
    // CLAUDE.md and LEARNING_SYSTEM.md instruct an interactive session to read
    // files and update databases. A tool-less JSON generator must not see them.
    let manifest = try JSONDecoder().decode(
        TeacherContext.Manifest.self,
        from: Data(ResourceLoader().text("teacher-context.json").utf8))
    #expect(!manifest.generation.contains { $0.hasSuffix("CLAUDE.md") })
    #expect(!manifest.grading.contains { $0.hasSuffix("CLAUDE.md") })
    #expect(!manifest.generation.contains { $0.hasSuffix("LEARNING_SYSTEM.md") })
    #expect(!manifest.grading.contains { $0.hasSuffix("LEARNING_SYSTEM.md") })
}
