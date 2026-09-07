import Foundation
import FluentCore

/// The learner profiles on this machine.
///
/// The list is derived by scanning `profiles/*/learner-profile.json` rather than
/// kept in an index. An index would be a second answer to "which profiles exist",
/// and the directory is already the first one.
@MainActor
final class ProfileStore {
    struct Profile: Identifiable, Equatable {
        let id: String
        let identity: LearnerIdentity
        let directory: URL
    }

    enum Failure: LocalizedError {
        case noFluent
        case seedFailed(String)

        var errorDescription: String? {
            switch self {
            case .noFluent:
                "Couldn't find Fluent. Reinstall the app, or set FLUENT_KIT_ROOT."
            case let .seedFailed(detail):
                "Couldn't create the profile: \(detail)"
            }
        }
    }

    private let defaultsKey = "activeProfileID"
    private let profilesRoot: URL
    private let python: String

    init(profilesRoot: URL = Locations.profilesRoot, python: String = "/usr/bin/python3") {
        self.profilesRoot = profilesRoot
        self.python = python
    }

    func list() -> [Profile] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: profilesRoot, includingPropertiesForKeys: nil) else { return [] }

        // A directory with a live `.migrating` marker is half-copied. Listing it
        // would hand the learner a truncated profile as their real one.
        let inFlight = Set(entries.filter { $0.pathExtension == "migrating" }
            .map { $0.deletingPathExtension().lastPathComponent })

        return entries.compactMap { directory -> Profile? in
            guard directory.pathExtension != "migrating",
                  !inFlight.contains(directory.lastPathComponent),
                  let data = try? Data(contentsOf:
                    directory.appending(path: "learner-profile.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let learner = json["learner"] as? [String: Any],
                  let name = learner["name"] as? String,
                  let language = learner["target_language"] as? String
            else { return nil }
            return Profile(id: directory.lastPathComponent,
                           identity: LearnerIdentity(name: name, targetLanguage: language),
                           directory: directory)
        }
        .sorted { $0.id < $1.id }
    }

    /// Which profile is open on this Mac. A per-machine preference rather than
    /// learner state, so it lives in UserDefaults and not beside the databases.
    var activeID: String? {
        get { UserDefaults.standard.string(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Falls back to the first profile when the stored id names one that is gone,
    /// so deleting a directory in Finder degrades to "opens the other one" rather
    /// than "the app is empty and won't say why".
    var active: Profile? {
        let profiles = list()
        if let id = activeID, let match = profiles.first(where: { $0.id == id }) {
            return match
        }
        return profiles.first
    }

    func activate(_ id: String) { activeID = id }

    /// Seeds a new profile through Fluent's own `new_profile.py`.
    ///
    /// The app does not copy or edit the templates itself. Fluent owns the schema,
    /// and its script is what knows that the examples carry sample sessions and
    /// placeholder strings that must not reach a real profile.
    func create(
        identity: LearnerIdentity, currentLevel: String, targetLevel: String,
        nativeLanguage: String, explanationLanguage: String,
        motivation: String, learningStyle: String, timeline: String, dailyMinutes: Int,
        otherLanguages: [String], fluentRoot: URL?
    ) async throws -> Profile {
        guard let fluentRoot else { throw Failure.noFluent }
        let slug = ProfileSlug.unique(identity, taken: Set(list().map(\.id)))
        let directory = profilesRoot.appending(path: slug)

        var arguments = [
            fluentRoot.appending(path: ".claude/hooks/new_profile.py").path,
            "--data-dir", directory.path,
            "--name", identity.name,
            "--target-language", identity.targetLanguage,
            "--native-language", nativeLanguage,
            "--explanation-language", explanationLanguage,
            "--current-level", currentLevel,
            "--target-level", targetLevel,
            "--motivation", motivation,
            "--learning-style", learningStyle,
            "--timeline", timeline,
            "--daily-minutes", String(dailyMinutes),
        ]
        if !otherLanguages.isEmpty {
            arguments.append("--other-languages")
            arguments.append(contentsOf: otherLanguages)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDE_PLUGIN_ROOT"] = fluentRoot.path
        do {
            _ = try await Subprocess.run(python, arguments, environment: environment)
        } catch {
            throw Failure.seedFailed(error.localizedDescription)
        }
        return Profile(id: slug, identity: identity, directory: directory)
    }
}
