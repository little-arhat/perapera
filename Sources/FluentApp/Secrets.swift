import Foundation

/// Reads the OpenRouter key.
///
/// The environment first, then a 0600 file beside the profiles. An installed app
/// has no repo, so a key that only works from a checkout is a key that stops
/// working when the app is installed. A GUI app never sources a login shell, so
/// the file is the normal path rather than the fallback.
///
/// Fluent-specific by name, so revoking it cannot break other projects.
enum Secrets {
    static let openRouterKey = "OPENROUTER_FLUENT"

    static func openRouter() -> String {
        if let value = ProcessInfo.processInfo.environment[openRouterKey],
           !value.isEmpty {
            return value
        }
        guard let contents = try? String(contentsOf: Locations.credentialsFile,
                                         encoding: .utf8) else {
            return ""
        }
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            let withoutExport = trimmed.hasPrefix("export ")
                ? String(trimmed.dropFirst("export ".count)) : trimmed
            guard withoutExport.hasPrefix("\(openRouterKey)=") else { continue }
            return String(withoutExport.dropFirst(openRouterKey.count + 1))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        return ""
    }

    /// Writes the key, owner-readable only, keeping any other line in the file.
    ///
    /// Created at 0600 rather than chmod'ed afterwards: `write(atomically:)` would
    /// leave the secret readable in a 0644 temp file for the moment in between.
    static func setOpenRouter(_ value: String) throws {
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
}
