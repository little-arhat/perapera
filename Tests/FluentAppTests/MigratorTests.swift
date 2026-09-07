import Foundation
import Testing
@testable import FluentApp

// This is the code that moves data nobody can regenerate. Every case here is a
// way it could quietly lose or corrupt a learner's history.

private struct Tree {
    let root: URL
    let legacy: URL
    let profiles: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "mig-\(UUID().uuidString)")
        legacy = root.appending(path: "fluent-data")
        profiles = root.appending(path: "profiles")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    }

    func seed(name: String = "Roma", language: String = "Japanese") throws {
        let profile = """
            {"learner": {"name": "\(name)", "target_language": "\(language)"},
             "current_streak_days": 4}
            """
        try profile.write(to: legacy.appending(path: "learner-profile.json"),
                          atomically: true, encoding: .utf8)
        let lessons = legacy.appending(path: "lessons")
        try FileManager.default.createDirectory(at: lessons, withIntermediateDirectories: true)
        try "{\"id\":\"one\"}".write(to: lessons.appending(path: "one.json"),
                                     atomically: true, encoding: .utf8)
    }

    var migrator: Migrator {
        Migrator(legacy: legacy, profilesRoot: profiles,
                 logFile: root.appending(path: "migration.log"))
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

@Test func migratesAndRetiresTheOriginal() throws {
    let tree = try Tree(); defer { tree.cleanUp() }
    try tree.seed()

    let outcome = try tree.migrator.run()
    guard case let .migrated(slug, destination, retired) = outcome else {
        Issue.record("expected a migration, got \(outcome)"); return
    }
    #expect(slug == "roma-japanese")
    #expect(FileManager.default.fileExists(
        atPath: destination.appending(path: "lessons/one.json").path))
    // The original must not remain readable at a path both surfaces default to.
    #expect(!FileManager.default.fileExists(atPath: tree.legacy.path))
    #expect(FileManager.default.fileExists(atPath: retired.appending(path: "README.txt").path))
}

@Test func theReportedRetiredPathIsTheOneThatExists() throws {
    // Recomputing the name after the move bumps the collision suffix and names a
    // directory that was never created.
    let tree = try Tree(); defer { tree.cleanUp() }
    try tree.seed()
    guard case let .migrated(_, _, retired) = try tree.migrator.run() else {
        Issue.record("expected a migration"); return
    }
    #expect(FileManager.default.fileExists(atPath: retired.path))
}

@Test func aSecondMigrationOnTheSameDayDoesNotCollide() throws {
    let tree = try Tree(); defer { tree.cleanUp() }
    try tree.seed()
    _ = try tree.migrator.run()

    // A second legacy directory appears (a restore, say) for a different learner.
    try FileManager.default.createDirectory(at: tree.legacy, withIntermediateDirectories: true)
    try tree.seed(name: "Ana", language: "Spanish")
    guard case let .migrated(slug, _, retired) = try tree.migrator.run() else {
        Issue.record("expected a second migration"); return
    }
    #expect(slug == "ana-spanish")
    #expect(FileManager.default.fileExists(atPath: retired.path))
}

@Test func runsOnceAndOnlyOnce() throws {
    let tree = try Tree(); defer { tree.cleanUp() }
    try tree.seed()
    _ = try tree.migrator.run()
    #expect(try tree.migrator.run() == .nothingToDo("nothing to migrate"))
}

@Test func verificationCatchesATruncatedFile() throws {
    // Counting files would pass this. A half-written image or a JSON file cut
    // short is exactly what a crash mid-copy leaves behind.
    let tree = try Tree(); defer { tree.cleanUp() }
    try tree.seed()

    let copy = tree.root.appending(path: "copy")
    try FileManager.default.copyItem(at: tree.legacy, to: copy)
    #expect(try tree.migrator.verify(source: tree.legacy, copy: copy).isEmpty)

    try "trunc".write(to: copy.appending(path: "lessons/one.json"),
                      atomically: true, encoding: .utf8)
    #expect(try tree.migrator.verify(source: tree.legacy, copy: copy)
            == ["lessons/one.json"])

    try FileManager.default.removeItem(at: copy.appending(path: "learner-profile.json"))
    #expect(try tree.migrator.verify(source: tree.legacy, copy: copy).count == 2)
}

@Test func anExistingProfileMeansAlreadyMigrated() throws {
    // A destination with no in-flight marker is a finished migration, not a
    // corrupt one; the legacy directory must be left alone for a person to look at.
    let tree = try Tree(); defer { tree.cleanUp() }
    try tree.seed()
    let destination = tree.profiles.appending(path: "roma-japanese")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try "{}".write(to: destination.appending(path: "learner-profile.json"),
                   atomically: true, encoding: .utf8)

    #expect(try tree.migrator.run() == .nothingToDo("already migrated"))
    #expect(FileManager.default.fileExists(
        atPath: tree.legacy.appending(path: "learner-profile.json").path))
}

@Test func aCrashDuringTheCopyIsRestartedNotAccepted() throws {
    // The case that matters. A half-copied profile whose learner-profile.json
    // already landed would otherwise list as real and be opened as live data.
    let tree = try Tree(); defer { tree.cleanUp() }
    try tree.seed()

    let destination = tree.profiles.appending(path: "roma-japanese")
    try FileManager.default.createDirectory(at: tree.profiles, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try "{\"learner\": {\"name\": \"Roma\", \"target_language\": \"Japanese\"}}"
        .write(to: destination.appending(path: "learner-profile.json"),
               atomically: true, encoding: .utf8)
    try Data().write(to: destination.appendingPathExtension("migrating"))

    guard case let .migrated(_, dest, _) = try tree.migrator.run() else {
        Issue.record("expected the interrupted copy to be redone"); return
    }
    // Redone in full, not left half-copied.
    #expect(FileManager.default.fileExists(atPath: dest.appending(path: "lessons/one.json").path))
    #expect(!FileManager.default.fileExists(
        atPath: dest.appendingPathExtension("migrating").path))
}

@Test func aCrashAfterTheRetireJustClearsTheMarker() throws {
    let tree = try Tree(); defer { tree.cleanUp() }
    let destination = tree.profiles.appending(path: "roma-japanese")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try "{\"learner\": {\"name\": \"Roma\", \"target_language\": \"Japanese\"}}"
        .write(to: destination.appending(path: "learner-profile.json"),
               atomically: true, encoding: .utf8)
    try Data().write(to: destination.appendingPathExtension("migrating"))
    try FileManager.default.removeItem(at: tree.legacy)   // already retired

    _ = try tree.migrator.run()
    #expect(!FileManager.default.fileExists(
        atPath: destination.appendingPathExtension("migrating").path))
    #expect(FileManager.default.fileExists(
        atPath: destination.appending(path: "learner-profile.json").path))
}

@Test func anUnreadableLegacyProfileIsLeftForAPerson() throws {
    let tree = try Tree(); defer { tree.cleanUp() }
    try "not json".write(to: tree.legacy.appending(path: "learner-profile.json"),
                         atomically: true, encoding: .utf8)
    #expect(try tree.migrator.run() == .nothingToDo("legacy profile unreadable"))
    #expect(FileManager.default.fileExists(atPath: tree.legacy.path))
}


@Test func anEmptyDirectoryDoesNotBlockTheMigration() throws {
    // A terminal session pointed at the new location before the move runs
    // creates the directory with nothing in it. Treating that as "already
    // migrated" would strand the learner's real data in the old location forever.
    let tree = try Tree(); defer { tree.cleanUp() }
    try tree.seed()
    try FileManager.default.createDirectory(
        at: tree.profiles.appending(path: "roma-japanese"), withIntermediateDirectories: true)

    guard case .migrated = try tree.migrator.run() else {
        Issue.record("an empty directory blocked the migration"); return
    }
    #expect(FileManager.default.fileExists(
        atPath: tree.profiles.appending(path: "roma-japanese/lessons/one.json").path))
}
