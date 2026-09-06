import Foundation

/// Where the app finds Fluent.
///
/// Mirrors `.claude/hooks/fluent_paths.py` deliberately and minimally: the app
/// must read the same databases the CLI writes, so the precedence rules have to
/// agree. Kept to the two facts the app needs -- where the data lives and where
/// the repo lives -- rather than re-deriving the Python module's full behavior.
enum Paths {
    /// Precedence: `$FLUENT_DATA_DIR`, then a repo-local `data/` that actually
    /// holds a profile, then the plugin-install default.
    static func dataDirectory(pluginRoot: URL) -> URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["FLUENT_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let repoData = pluginRoot.appending(path: "data")
        if FileManager.default.fileExists(
            atPath: repoData.appending(path: "learner-profile.json").path) {
            return repoData
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/fluent-data")
    }

    /// The Fluent repo. A GUI app has no useful working directory, so this is a
    /// stored setting with a sensible default rather than something inferred.
    static func defaultPluginRoot() -> URL {
        if let env = ProcessInfo.processInfo.environment["CLAUDE_PLUGIN_ROOT"],
           !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "prj/p/lang/fluent")
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
