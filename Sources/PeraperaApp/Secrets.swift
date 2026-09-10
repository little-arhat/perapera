import Foundation
import Security

/// Reads and writes the OpenRouter key.
///
/// A 0600 file beside the profiles, not the Keychain.
///
/// The Keychain is the better store *for an app with a stable code-signing
/// identity*. This one is ad-hoc signed, so its hash changes on every build and
/// macOS sees a different app each time — which means an authorization prompt at
/// every launch. That is worse than the file it replaced, and worse in a way the
/// learner pays for daily. Getting the Keychain back means getting a persistent
/// signing identity first; until then the file is the honest choice.
///
/// A key already in the Keychain from that attempt is adopted on first read and
/// the item deleted, so there is one copy and no more prompts.
///
/// Fluent-specific by name, so revoking it cannot break other projects.
enum Secrets {
    static let openRouterKey = "OPENROUTER_FLUENT"

    private static let legacyService = "dev.perapera.app"
    private static let olderService = "dev.fluent.app"

    /// Environment first, so a shell can override without touching the store.
    static func openRouter() -> String {
        if let value = ProcessInfo.processInfo.environment[openRouterKey],
           !value.isEmpty {
            return value
        }
        if let stored = readFile() { return stored }
        if let rescued = adoptFromKeychain() { return rescued }
        return ""
    }

    static func setOpenRouter(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.empty }
        try writeFile(trimmed)
    }

    enum Failure: LocalizedError {
        case empty
        var errorDescription: String? { "That key is empty." }
    }

    // MARK: - The file

    private static func readFile() -> String? {
        guard let contents = try? String(contentsOf: Locations.credentialsFile,
                                         encoding: .utf8) else { return nil }
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            let withoutExport = trimmed.hasPrefix("export ")
                ? String(trimmed.dropFirst("export ".count)) : trimmed
            guard withoutExport.hasPrefix("\(openRouterKey)=") else { continue }
            let value = String(withoutExport.dropFirst(openRouterKey.count + 1))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"\' "))
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Writes the key, owner-readable only, keeping any other line in the file.
    ///
    /// Created at 0600 rather than chmod'ed afterwards: `write(atomically:)`
    /// would leave the secret in a 0644 temp file for the moment in between.
    private static func writeFile(_ value: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Locations.stateRoot, withIntermediateDirectories: true)

        var lines = (try? String(contentsOf: Locations.credentialsFile, encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init) ?? []
        lines.removeAll { $0.trimmingCharacters(in: .whitespaces)
            .hasPrefix("\(openRouterKey)=") }
        lines.removeAll { $0.isEmpty }
        lines.append("\(openRouterKey)=\(value)")

        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        try? fm.removeItem(at: Locations.credentialsFile)
        guard fm.createFile(atPath: Locations.credentialsFile.path, contents: data,
                            attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    // MARK: - Getting back out of the Keychain

    /// Moves a key out of the Keychain and into the file, once.
    ///
    /// This is the prompt: reading the item is what macOS asks about. It happens
    /// at most once, because the item is deleted afterwards.
    private static func adoptFromKeychain() -> String? {
        for service in [legacyService, olderService] {
            guard let value = readKeychain(service: service) else { continue }
            guard (try? writeFile(value)) != nil else { return value }
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: openRouterKey,
            ] as CFDictionary)
            return value
        }
        return nil
    }

    private static func readKeychain(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: openRouterKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty
        else { return nil }
        return value
    }
}
