import Foundation

/// Reads the OpenRouter key.
///
/// Same rule as `tools/imgbench`: the environment first, then a gitignored
/// `.env` at the repo root. A GUI app never sources a login shell, so the file
/// is the normal path rather than the fallback.
///
/// Fluent-specific by name, so revoking it cannot break other projects.
enum Secrets {
    static let openRouterKey = "OPENROUTER_FLUENT"

    static func openRouter(repoRoot: URL) -> String {
        if let value = ProcessInfo.processInfo.environment[openRouterKey],
           !value.isEmpty {
            return value
        }
        let envFile = repoRoot.appending(path: ".env")
        guard let contents = try? String(contentsOf: envFile, encoding: .utf8) else {
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
}
