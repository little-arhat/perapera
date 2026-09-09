import Foundation

/// The teacher's brief: a preamble the app owns, plus documents Fluent owns.
///
/// Assembling it as a value keeps "what does the teacher know?" answerable by
/// reading one manifest, rather than by reasoning about which CLAUDE.md files a
/// working directory happens to sit under.
public enum TeacherBrief {
    public struct Document: Equatable, Sendable {
        public let name: String
        public let text: String

        public init(name: String, text: String) {
            self.name = name
            self.text = text
        }
    }

    public static func assemble(preamble: String, documents: [Document]) -> String {
        guard !documents.isEmpty else { return preamble }
        let body = documents
            .map { "# \($0.name)\n\n\($0.text.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n\n---\n\n")
        return "\(preamble)\n\n---\n\n\(body)"
    }
}
