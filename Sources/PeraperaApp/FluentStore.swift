import Foundation
import PeraperaCore

/// The bridge to Fluent's databases.
///
/// It owns no logic. SM-2, streaks, atomic writes, and backups all live in
/// `update-db.py`, which is tested and already the system of record; duplicating
/// any of it in Swift would create a second source of truth that drifts. This
/// type's whole job is to marshal values across the process boundary.
@MainActor
final class FluentStore {
    struct Config {
        var fluentRoot: URL
        var dataDirectory: URL
        var python: String = "/usr/bin/python3"

        var readScript: URL { fluentRoot.appending(path: ".claude/hooks/read-db.py") }
        var updateScript: URL { fluentRoot.appending(path: ".claude/hooks/update-db.py") }
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
            let progress_db: ProgressDB
            let spaced_repetition: SpacedRepetition
            let mistakes_db: MistakesDB
            let mastery_db: MasteryDB
            let session_log: SessionLog
        }

        /// What Fluent recorded about each finished session.
        ///
        /// `focus_next_session` is the important one: it is the teacher's own
        /// written instruction for what to do next, decided while looking at
        /// the learner's actual answers. The app ignored it for weeks.
        struct SessionLog: Decodable {
            let sessions: [Session]

            struct Session: Decodable {
                let session_id: String?
                let date: String?
                let accuracy: Double?
                let topics_covered: [String]?
                let focus_next_session: [String]?
                let breakthroughs: [String]?
                let notes: String?
            }
        }

        /// The record of how the learner is actually doing over time.
        ///
        /// Read but never written here: `update-db.py` owns every number in it.
        struct ProgressDB: Decodable {
            struct Overall: Decodable {
                let total_sessions: Int?
                let total_exercises: Int?
                let total_correct: Int?
                let accuracy_rate: Double?
                let total_study_minutes: Int?
                let average_session_duration: Int?
            }

            struct TrendPoint: Decodable {
                let date: String
                let accuracy: Double
                let exercises: Int?
            }

            struct SkillProgress: Decodable {
                let sessions: Int?
                let accuracy: Double?
                let last_practiced: String?
                let exercises_completed: Int?
            }

            let overall_stats: Overall?
            let accuracy_trend: [TrendPoint]?
            let skill_progress: [String: SkillProgress]?
        }

        struct MasteryDB: Decodable {
            let skills: [String: Skill]?

            struct Skill: Decodable {
                let mastery_level: Int?
                let avg_accuracy: Double?
            }
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

    /// Both coordinates are stated. Leaving `FLUENT_DATA_DIR` unset would let the
    /// scripts apply their own precedence and fall back to `~/.claude/fluent-data`,
    /// which once there is more than one profile is not "the same databases the
    /// CLI uses" but "some other learner's".
    private func environmentForScripts() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_PLUGIN_ROOT"] = config.fluentRoot.path
        env["FLUENT_DATA_DIR"] = config.dataDirectory.path
        return env
    }
}
