import Foundation
import Testing
@testable import PeraperaApp
@testable import PeraperaCore

// An opt-in integration test. It spends money and needs the network, so it is
// gated on PERAPERA_LIVE=1 and skipped otherwise:
//
//     PERAPERA_LIVE=1 swift test --filter live
//
// Everything else in the suite is offline and free. This one exists because the
// unit tests cannot answer the only question that matters after a refactor of
// this size: does a real `claude -p` call still come back as a lesson this app
// can render and grade?
//
// It works against a copy of the active profile. Generation writes the lesson
// to disk, and a test must not deposit one in a learner's real archive.

private func liveEnabled() -> Bool {
    ProcessInfo.processInfo.environment["PERAPERA_LIVE"] == "1"
}

@MainActor
private func scratchProfile() throws -> URL {
    let store = ProfileStore()
    guard let active = store.active else { throw CocoaError(.fileNoSuchFile) }
    let copy = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "live-\(UUID().uuidString)")
    try FileManager.default.copyItem(at: active.directory, to: copy)
    return copy
}

@MainActor
@Test func liveGenerationProducesALessonTheAppCanRender() async throws {
    guard liveEnabled() else { return }
    guard let fluentRoot = Locations.fluentRoot() else {
        Issue.record("no Fluent found; run `make app` or set FLUENT_KIT_ROOT")
        return
    }
    guard let claude = Subprocess.which("claude", extraPaths: Locations.toolSearchPaths) else {
        Issue.record("no `claude` on PATH"); return
    }

    let profile = try scratchProfile()
    defer { try? FileManager.default.removeItem(at: profile) }

    let service = LessonService(
        claude: ClaudeClient(config: .init(
            executable: claude,
            model: ProcessInfo.processInfo.environment["PERAPERA_LIVE_MODEL"] ?? "sonnet",
            maxBudgetUSD: 1.0,
            workingDirectory: profile)),
        grader: ClaudeClient(config: .init(
            executable: claude,
            model: ProcessInfo.processInfo.environment["PERAPERA_LIVE_MODEL"] ?? "sonnet",
            maxBudgetUSD: 1.0,
            workingDirectory: profile)),
        store: FluentStore(config: .init(fluentRoot: fluentRoot, dataDirectory: profile)),
        lessons: LessonStore(dataDirectory: profile),
        resources: ResourceLoader(),
        fluentRoot: fluentRoot,
        images: nil)

    let record = try await service.generate(
        spec: LessonSpec(mode: .lesson, size: .small, depth: .light,
                         focus: "counters and prices", photoExercises: 0))

    // The contract the app relies on, top to bottom.
    #expect(!record.lesson.title.isEmpty)
    #expect(!record.lesson.exercises.isEmpty)
    #expect(record.lesson.validate().isEmpty)
    #expect(record.state == .generated)

    // And it survives the round trip through the archive, which is what the
    // learner reopens tomorrow.
    let reloaded = try LessonStore(dataDirectory: profile).load(id: record.id)
    #expect(reloaded.lesson.exercises.count == record.lesson.exercises.count)

    // Every exercise must be answerable: the grader has to have something to
    // compare against, or the learner meets a dead end mid-lesson.
    for exercise in reloaded.lesson.exercises {
        #expect(!exercise.prompt.isEmpty, "exercise \(exercise.id) has no prompt")
    }
    print("live: \(record.lesson.exercises.count) exercises — \(record.lesson.title)")
}
