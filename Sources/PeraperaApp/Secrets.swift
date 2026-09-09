import Foundation
import Security

/// Reads and writes the OpenRouter key.
///
/// The Keychain is the store. It encrypts at rest and scopes access to this
/// app, which a file at 0600 does not: any process running as the learner can
/// read a plain file, and it lands in backups and in Time Machine as plaintext.
///
/// Fluent-specific by name, so revoking it cannot break other projects. One
/// copy: `tools/imgbench` reads the same Keychain item through the `security`
/// command rather than keeping a second file that has to be rotated in step.
enum Secrets {
    static let openRouterKey = "OPENROUTER_FLUENT"

    private static let service = "dev.perapera.app"
    private static let account = openRouterKey

    /// Environment first, so a shell can override without touching the store,
    /// then the Keychain, then the file this used to live in — which is read
    /// once, copied in, and deleted.
    static func openRouter() -> String {
        if let value = ProcessInfo.processInfo.environment[openRouterKey],
           !value.isEmpty {
            return value
        }
        if let stored = read() { return stored }
        if let carried = adoptPreviousService() { return carried }
        if let migrated = adoptLegacyFile() { return migrated }
        return ""
    }

    /// The Keychain item is keyed by service, which was the bundle identifier
    /// before the rename. Moved rather than copied: one key, one place.
    private static func adoptPreviousService() -> String? {
        guard let value = read(service: Locations.previousBundleIdentifier),
              (try? write(value)) != nil
        else { return nil }
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Locations.previousBundleIdentifier,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        return value
    }

    static func setOpenRouter(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.empty }
        try write(trimmed)
    }

    enum Failure: LocalizedError {
        case empty
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .empty:
                "That key is empty."
            case let .keychain(status):
                "The Keychain refused to store the key (\(status)). "
                    + "Set OPENROUTER_FLUENT in the environment instead."
            }
        }
    }

    // MARK: - Keychain

    private static func read(service: String = Secrets.service) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    private static func write(_ value: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = base
            insert[kSecValueData as String] = data
            // Available whenever this Mac is unlocked, and never synced to
            // another device: the key belongs to this machine's setup.
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure.keychain(added) }
            return
        }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }

    // MARK: - The file this replaced

    /// Moves a key out of `credentials.env` and into the Keychain, once.
    ///
    /// The file is removed afterwards rather than left as a fallback: two copies
    /// of a secret is the problem this change exists to end, and a stale one is
    /// worse than none because rotating misses it.
    private static func adoptLegacyFile() -> String? {
        let file = Locations.credentialsFile
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else {
            return nil
        }
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            let withoutExport = trimmed.hasPrefix("export ")
                ? String(trimmed.dropFirst("export ".count)) : trimmed
            guard withoutExport.hasPrefix("\(openRouterKey)=") else { continue }
            let value = String(withoutExport.dropFirst(openRouterKey.count + 1))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            guard !value.isEmpty else { continue }
            guard (try? write(value)) != nil else { return value }
            try? FileManager.default.removeItem(at: file)
            return value
        }
        return nil
    }
}
