import Foundation

/// Where things are, now that "where things are" is four questions rather than one.
///
/// `Paths.dataDirectory(pluginRoot:)` answered all four with one setting: the repo
/// held the databases, the scripts, the prompts and the key. An installed app has
/// no repo, and a learner may have more than one profile, so each concept gets its
/// own resolver and its own override.
enum Locations {
    /// The bundle identifier this app shipped under before it was named
    /// Perapera. `UserDefaults` and the Keychain are both keyed by it, so the
    /// rename would otherwise have silently reset every preference and lost the
    /// stored API key.
    static let previousBundleIdentifier = "dev.fluent.app"

    /// `$XDG_DATA_HOME/perapera`, defaulting to `~/.local/share/perapera`.
    ///
    /// Not `~/Library/Application Support`, despite this being a macOS app. The
    /// same directory is read by Python hooks and five Fluent skills driven from
    /// a shell, and that path contains a space every one of them has to quote.
    /// The macOS location buys nothing back: Time Machine and Migration Assistant
    /// take the whole home directory, dotfiles included.
    static var stateRoot: URL {
        let env = ProcessInfo.processInfo.environment
        let dataHome: URL
        if let xdg = env["XDG_DATA_HOME"], !xdg.isEmpty {
            dataHome = URL(fileURLWithPath: (xdg as NSString).expandingTildeInPath)
        } else {
            dataHome = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".local/share")
        }
        return dataHome.appending(path: "perapera")
    }

    static var profilesRoot: URL { stateRoot.appending(path: "profiles") }
    static var credentialsFile: URL { stateRoot.appending(path: "credentials.env") }
    static var migrationLog: URL { stateRoot.appending(path: "migration.log") }

    /// Where learner state lived before 2026-09. Read once, by the migrator.
    static var legacyDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/fluent-data")
    }

    /// Fluent: `update-db.py`, `read-db.py`, `new_profile.py`, the templates, and
    /// the methodology the teacher is briefed with.
    ///
    /// Nil rather than a guess. A wrong path fails at the first subprocess with an
    /// unreadable error; nil fails at launch with a sentence that says what to do.
    static func fluentRoot() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let override = env["FLUENT_KIT_ROOT"], !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            return isFluent(url) ? url : nil
        }
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appending(path: "fluent")
            if isFluent(bundled) { return bundled }
        }
        return nil
    }

    /// A directory is Fluent if it can do the things the app needs of it.
    private static func isFluent(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appending(path: ".claude/hooks/update-db.py").path)
            && fm.fileExists(atPath: url.appending(path: ".claude/hooks/new_profile.py").path)
            && fm.fileExists(atPath: url.appending(path: "data-examples").path)
    }

    /// Homebrew and the usual installs, for locating `claude` when the app's
    /// inherited PATH is the minimal GUI one.
    static let toolSearchPaths = [
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".brew/bin").path,
        "/opt/homebrew/bin",
        "/usr/local/bin",
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin").path,
    ]
}
