import CryptoKit
import Foundation

/// Who a profile belongs to, and what they are learning.
///
/// One learner studying two languages is two profiles: `learner-profile.json`
/// holds exactly one `target_language`, and all six databases are keyed to it.
public struct LearnerIdentity: Equatable, Sendable {
    public let name: String
    public let targetLanguage: String

    public init(name: String, targetLanguage: String) {
        self.name = name
        self.targetLanguage = targetLanguage
    }
}

/// The directory name a profile lives under.
///
/// Human-readable on purpose: this is a path the learner sees in Finder and
/// pastes into a shell. A UUID would be easier to generate and worse to live with.
public enum ProfileSlug {
    public static func make(_ identity: LearnerIdentity) -> String {
        let joined = "\(identity.name)-\(identity.targetLanguage)"
        let folded = joined
            .folding(options: [.diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        var slug = ""
        var lastWasDash = false
        for scalar in folded.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash, !slug.isEmpty {
                slug.append("-")
                lastWasDash = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }

        guard slug.isEmpty else { return slug }
        // A name with no ASCII folds away entirely, and `ローマ` learning `日本語`
        // is not hypothetical for this app. The fallback must be a *stable*
        // digest: String.hashValue is seeded per process, so it would name a new
        // directory on every launch and orphan the learner's data each time.
        let digest = SHA256.hash(data: Data(joined.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "profile-\(digest.prefix(12))"
    }

    public static func unique(_ identity: LearnerIdentity, taken: Set<String>) -> String {
        let base = make(identity)
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }
}

/// Whether the one-shot move out of the legacy data directory should run.
///
/// A value rather than a side effect, so the rule is testable without a
/// filesystem and readable without tracing the copy.
public enum MigrationDecision: Equatable, Sendable {
    case migrate(slug: String)
    case skip(String)

    public static func decide(
        legacyHasProfile: Bool, existingSlugs: Set<String>, identity: LearnerIdentity?
    ) -> MigrationDecision {
        guard legacyHasProfile else { return .skip("nothing to migrate") }
        guard let identity else { return .skip("legacy profile unreadable") }
        let slug = ProfileSlug.make(identity)
        guard !existingSlugs.contains(slug) else { return .skip("already migrated") }
        return .migrate(slug: slug)
    }
}
