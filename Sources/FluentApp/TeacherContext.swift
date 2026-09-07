import Foundation
import FluentCore

/// Reads the manifest and the Fluent documents it names.
///
/// A missing document throws rather than being skipped. Shipping a shorter brief
/// would change how every lesson is taught and leave nothing in the output to
/// show for it.
///
/// Fluent's own `CLAUDE.md` and `LEARNING_SYSTEM.md` are deliberately absent from
/// the manifest: they instruct an interactive terminal session to read files,
/// greet the learner and update six databases. Handing that to a tool-less JSON
/// generator briefs it for the wrong surface.
enum TeacherContext {
    enum Call: String, Sendable { case generation, grading }

    struct Manifest: Decodable {
        let preamble: String
        let generation: [String]
        let grading: [String]

        func documents(for call: Call) -> [String] {
            switch call {
            case .generation: generation
            case .grading: grading
            }
        }
    }

    enum Failure: LocalizedError, Equatable {
        case missing(String)

        var errorDescription: String? {
            switch self {
            case let .missing(path):
                "Fluent is missing \(path), which the teacher's brief needs."
            }
        }
    }

    static func systemPrompt(
        fluentRoot: URL, call: Call, resources: ResourceLoader = ResourceLoader()
    ) throws -> String {
        let manifest = try JSONDecoder().decode(
            Manifest.self, from: Data(resources.text("teacher-context.json").utf8))
        let documents = try manifest.documents(for: call).map { relative in
            guard let text = try? String(contentsOf: fluentRoot.appending(path: relative),
                                         encoding: .utf8) else {
                throw Failure.missing(relative)
            }
            return TeacherBrief.Document(name: relative, text: text)
        }
        return TeacherBrief.assemble(preamble: manifest.preamble, documents: documents)
    }
}
