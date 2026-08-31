import Foundation
import FluentCore

/// The bridge to Fluent's databases.
///
/// It owns no logic. SM-2, streaks, atomic writes, and backups all live in
/// `update-db.py`, which is tested and already the system of record; duplicating
/// any of it in Swift would create a second source of truth that drifts. This
/// type's whole job is to marshal values across the process boundary.
@MainActor
final class FluentStore {
    struct Config {
        var pluginRoot: URL
        var python: String = "/usr/bin/python3"

        var readScript: URL { pluginRoot.appending(path: ".claude/hooks/read-db.py") }
        var updateScript: URL { pluginRoot.appending(path: ".claude/hooks/update-db.py") }
    }

    private let config: Config

    init(config: Config) {
        self.config = config
    }

    // MARK: - Reading

    /// The subset of Fluent's state the app actually uses. Deliberately partial:
    /// decoding only what we consume means a new field upstream cannot break the
    /// app, and an unused one cannot silently rot here.
    struct Snapshot: Decodable {
        struct Databases: Decodable {
            let learner_profile: Profile
            let spaced_repetition: SpacedRepetition
            let mistakes_db: MistakesDB
        }

        struct Profile: Decodable {
            struct Learner: Decodable {
                let name: String
                let target_language: String
                let native_language: String?
                let other_languages: [String]?
                let explanation_language: String?
                let current_level: String
                let target_level: String
                let motivation: String?
                let learning_style: String?
            }
            let learner: Learner
            let current_streak_days: Int
            let total_sessions: Int
        }

        struct SpacedRepetition: Decodable {
            let items: [String: Item]

            struct Item: Decodable {
                let id: String
                let type: String?
                let content: String
                let answer: String
                let category: String?
                let priority: String?
                let mastery_level: Int?
                let due_date: String?
            }
        }

        struct MistakesDB: Decodable {
            let error_patterns: [String: Pattern]

            struct Pattern: Decodable {
                let category: String?
                let frequency: Int?
                let mastery_level: Int?
                let notes: String?
            }
        }

        struct Computed: Decodable {
            let today: String
            let due_reviews_count: Int
            let due_review_items: [String]
            let next_session_id: String
            let streak_active: Bool
        }

        let databases: Databases
        let computed: Computed
    }

    func load() async throws -> Snapshot {
        let result = try await Subprocess.run(
            config.python, [config.readScript.path],
            environment: environmentForScripts()
        )
        return try JSONDecoder().decode(Snapshot.self, from: Data(result.stdout.utf8))
    }

    // MARK: - Writing

    /// Submits one finished lesson as one Fluent session.
    ///
    /// `update-db.py` is the single writer; this sends it a report and reads
    /// back its summary lines. Same-session-id calls replace, so a retry after a
    /// crash is safe rather than double-counting.
    @discardableResult
    func submit(_ report: SessionReport) async throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(report)

        let result = try await Subprocess.run(
            config.python, [config.updateScript.path],
            input: payload,
            environment: environmentForScripts()
        )
        return result.stdout
    }

    /// `CLAUDE_PLUGIN_ROOT` is how the hooks find the repo; `FLUENT_DATA_DIR`
    /// stays unset so `fluent_paths` applies its normal precedence and the app
    /// reads exactly the databases the CLI does.
    private func environmentForScripts() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_PLUGIN_ROOT"] = config.pluginRoot.path
        return env
    }
}
