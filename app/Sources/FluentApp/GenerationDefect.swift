import Foundation
import FluentCore

/// A generated lesson that decoded fine but is not worth showing.
///
/// Distinct from a decode failure: the JSON was well-formed, the content was
/// not. Both are worth one retry, because both are stochastic.
struct GenerationDefect: LocalizedError {
    let defects: [Lesson.Defect]

    var errorDescription: String? {
        "The generated lesson had problems:\n"
            + defects.map { "• \($0.description)" }.joined(separator: "\n")
    }
}
