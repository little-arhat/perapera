import CryptoKit
import Foundation
import FluentCore

/// The one-shot move out of `~/.claude/fluent-data`.
///
/// Copies, compares every file's digest, and only then retires the old directory
/// by renaming it. The rename is the point: both the app and the CLI resolve the
/// old path as a default, so a readable copy left behind invites a split brain
/// where the terminal advances one set of databases and the app another.
///
/// Paths are injected rather than read from `Locations`, so the whole thing is
/// testable against a temporary tree. It is not `@MainActor`: hashing every file
/// of a profile with a few hundred images would visibly hang a launch.
struct Migrator {
    let legacy: URL
    let profilesRoot: URL
    let logFile: URL

    enum Outcome: Equatable {
        case nothingToDo(String)
        case migrated(slug: String, destination: URL, retired: URL)
    }

    enum Failure: LocalizedError, Equatable {
        case verificationFailed([String])

        var errorDescription: String? {
            switch self {
            case let .verificationFailed(files):
                "The copy didn't match for: \(files.prefix(5).joined(separator: ", "))"
                    + (files.count > 5 ? " (and \(files.count - 5) more)" : "")
                    + ". Nothing was removed; your data is still where it was."
            }
        }
    }

    private var fm: FileManager { .default }

    /// Marker written before the copy starts and removed after the retire. Its
    /// presence means "a migration was in flight here and did not finish".
    private func marker(for destination: URL) -> URL {
        destination.appendingPathExtension("migrating")
    }

    func run() throws -> Outcome {
        try resumeIfInterrupted()

        let profileFile = legacy.appending(path: "learner-profile.json")
        let decision = MigrationDecision.decide(
            legacyHasProfile: fm.fileExists(atPath: profileFile.path),
            existingSlugs: Set(completedSlugs()),
            identity: readIdentity(at: profileFile))

        guard case let .migrate(slug) = decision else {
            if case let .skip(reason) = decision { return .nothingToDo(reason) }
            return .nothingToDo("nothing to migrate")
        }

        let destination = profilesRoot.appending(path: slug)
        try fm.createDirectory(at: profilesRoot, withIntermediateDirectories: true)
        // `decide` only returns .migrate when the destination holds no profile,
        // so anything sitting there is an empty directory a terminal session
        // created by resolving the new path early. copyItem refuses to write into
        // an existing directory at all, so it has to go.
        try? fm.removeItem(at: destination)
        try Data().write(to: marker(for: destination))
        try fm.copyItem(at: legacy, to: destination)

        let mismatches = try verify(source: legacy, copy: destination)
        guard mismatches.isEmpty else {
            try? fm.removeItem(at: destination)
            try? fm.removeItem(at: marker(for: destination))
            throw Failure.verificationFailed(mismatches)
        }

        let retired = try retire(legacy, movedTo: destination)
        try? fm.removeItem(at: marker(for: destination))
        log("migrated \(legacy.path) -> \(destination.path), old copy at \(retired.path)")
        return .migrated(slug: slug, destination: destination, retired: retired)
    }

    /// Finishes, or restarts, a migration that died part-way.
    ///
    /// A crash *during* the copy is the case that matters, and it leaves a
    /// half-copied profile whose `learner-profile.json` is likely already there —
    /// so it would list as a real profile and be opened as live data. While the
    /// legacy directory still exists it remains authoritative, so the answer is
    /// to throw the partial copy away and start again, never to verify it and
    /// give up.
    func resumeIfInterrupted() throws {
        for marker in markers() {
            let destination = marker.deletingPathExtension()
            if fm.fileExists(atPath: legacy.path) {
                try? fm.removeItem(at: destination)
                try? fm.removeItem(at: marker)
                log("discarded an unfinished copy at \(destination.path); "
                    + "the original is intact and will be migrated again")
            } else {
                // The copy finished and the original was already retired; only
                // the marker is left over.
                try? fm.removeItem(at: marker)
                log("cleared a stale marker at \(marker.path)")
            }
        }
    }

    private func markers() -> [URL] {
        (try? fm.contentsOfDirectory(at: profilesRoot, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "migrating" } ?? []
    }

    /// Profile directories that hold an actual profile and have no migration in
    /// flight.
    ///
    /// Both conditions matter. A half-copied directory must not count as "already
    /// migrated", and neither must an empty one: a terminal session pointed at the
    /// new location before the move runs would create the directory with no
    /// databases in it, and a bare name check would then block the real migration
    /// permanently.
    private func completedSlugs() -> [String] {
        let inFlight = Set(markers().map { $0.deletingPathExtension().lastPathComponent })
        let entries = (try? fm.contentsOfDirectory(
            at: profilesRoot, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { $0.pathExtension != "migrating" }
            .filter { fm.fileExists(atPath: $0.appending(path: "learner-profile.json").path) }
            .map(\.lastPathComponent)
            .filter { !inFlight.contains($0) }
    }

    private func readIdentity(at url: URL) -> LearnerIdentity? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let learner = json["learner"] as? [String: Any],
              let name = learner["name"] as? String,
              let language = learner["target_language"] as? String
        else { return nil }
        return LearnerIdentity(name: name, targetLanguage: language)
    }

    /// Every regular file under `source` must exist under `copy` with the same
    /// SHA-256. Counting files is not enough: a truncated image passes a count.
    func verify(source: URL, copy: URL) throws -> [String] {
        guard let walker = fm.enumerator(
            at: source, includingPropertiesForKeys: [.isRegularFileKey])
        else { return ["<could not enumerate>"] }

        // Path components of the resolved source, not string arithmetic on
        // `.path`. The enumerator hands back `/private/var/...` for a source
        // given as `/var/...`, so subtracting the prefix by length silently
        // shifts every relative path by eight characters and reports every file
        // as missing.
        let base = source.resolvingSymlinksInPath().pathComponents

        var mismatches: [String] = []
        for case let file as URL in walker {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?
                .isRegularFile == true else { continue }
            let components = file.resolvingSymlinksInPath().pathComponents
            guard components.count > base.count,
                  Array(components.prefix(base.count)) == base else { continue }
            let relative = components.dropFirst(base.count).joined(separator: "/")
            let target = copy.appending(path: relative)
            guard let a = try? Data(contentsOf: file),
                  let b = try? Data(contentsOf: target),
                  SHA256.hash(data: a) == SHA256.hash(data: b)
            else { mismatches.append(relative); continue }
        }
        return mismatches
    }

    /// Renames the legacy directory out of the way and returns where it went.
    ///
    /// Returns it rather than recomputing: a second call would see the directory
    /// it just created, bump the collision suffix, and name a path that does not
    /// exist in the message shown to the learner.
    private func retire(_ legacy: URL, movedTo destination: URL) throws -> URL {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")   // never a non-Gregorian year
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let base = legacy.deletingLastPathComponent()
        let name = "\(legacy.lastPathComponent).migrated-\(stamp.string(from: Date()))"

        var retired = base.appending(path: name)
        var n = 2
        while fm.fileExists(atPath: retired.path) {
            retired = base.appending(path: "\(name)-\(n)")
            n += 1
        }

        try fm.moveItem(at: legacy, to: retired)
        let note = """
            This directory is a retired copy of Fluent's learning data.

            The live data moved to:
              \(destination.path)

            Nothing reads this directory any more. It is kept so the move is
            reversible; delete it once you are satisfied nothing was lost.
            """
        try? note.write(to: retired.appending(path: "README.txt"),
                        atomically: true, encoding: .utf8)
        return retired
    }

    private func log(_ line: String) {
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        try? fm.createDirectory(at: logFile.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? stamped.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }
}
