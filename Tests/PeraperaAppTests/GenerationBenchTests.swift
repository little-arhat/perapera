import Foundation
import Testing
@testable import PeraperaApp
@testable import PeraperaCore

// Two questions the TODO has been carrying, both answerable only by paying for
// generations: is Opus worth its price over Sonnet (FL-3), and does the
// methodology brief earn the tokens it costs (FL-30)?
//
// Opt in, because it spends money:
//
//     PERAPERA_BENCH=1 swift test --filter bench
//
// Results land in ~/perapera-bench/<timestamp>/ as the lessons themselves plus a
// summary, so the judgement about quality is made by reading them rather than by
// a metric standing in for reading them.

private struct Config {
    let name: String
    let model: String
    let withBrief: Bool
}

/// A resources directory whose manifest names no documents, so the teacher is
/// briefed with the preamble alone. Uses the existing FLUENT_APP_RESOURCES
/// override rather than adding a switch to production code.
@MainActor
private func briefless() throws -> ResourceLoader {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "nobrief-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let manifest = try ResourceLoader().text("teacher-context.json")
    var json = try JSONSerialization.jsonObject(with: Data(manifest.utf8)) as! [String: Any]
    json["generation"] = [String]()
    json["grading"] = [String]()
    try JSONSerialization.data(withJSONObject: json)
        .write(to: dir.appending(path: "teacher-context.json"))
    // Prompts and schemas still have to resolve; the loader falls through to the
    // bundle for anything the override does not hold.
    return ResourceLoader(override: dir)
}

@MainActor
@Test func benchGenerationCostAndQuality() async throws {
    guard ProcessInfo.processInfo.environment["PERAPERA_BENCH"] == "1" else { return }
    guard let fluentRoot = Locations.fluentRoot(),
          let claude = Subprocess.which("claude", extraPaths: Locations.toolSearchPaths)
    else { Issue.record("need Fluent and claude"); return }

    let store = ProfileStore()
    guard let active = store.active else { Issue.record("no profile"); return }

    let stamp = ISO8601DateFormatter()
    stamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
    let out = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "perapera-bench/\(Int(Date().timeIntervalSince1970))")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    // PERAPERA_BENCH_ONLY names one config, so a run that died part-way can be
    // finished without paying for the ones that already succeeded.
    let only = ProcessInfo.processInfo.environment["PERAPERA_BENCH_ONLY"]
    let configs = [
        Config(name: "opus-brief", model: "opus", withBrief: true),
        Config(name: "sonnet-brief", model: "sonnet", withBrief: true),
        Config(name: "sonnet-nobrief", model: "sonnet", withBrief: false),
    ]

    var summary = ["config,cost_usd,exercises,requested,defects,skills,seconds"]
    for config in configs where only == nil || only == config.name {
        let scratch = out.appending(path: config.name)
        try FileManager.default.copyItem(at: active.directory, to: scratch)

        // The spend callback fires on the subprocess reader thread, so the
        // total is a lock rather than a captured var.
        let spent = Tally()
        let began = Date()
        let service = LessonService(
            claude: ClaudeClient(config: .init(executable: claude, model: config.model,
                                               maxBudgetUSD: 2.0, workingDirectory: scratch)),
            grader: ClaudeClient(config: .init(executable: claude, model: config.model,
                                               maxBudgetUSD: 2.0, workingDirectory: scratch)),
            store: FluentStore(config: .init(fluentRoot: fluentRoot, dataDirectory: scratch)),
            lessons: LessonStore(dataDirectory: scratch),
            resources: config.withBrief ? ResourceLoader() : (try briefless()),
            fluentRoot: fluentRoot,
            images: nil)

        // The same request every time, so the only variables are the two under
        // test. A generation that fails validation is a result, not a reason to
        // abandon the run: "this configuration produces unusable lessons" is
        // exactly what the comparison is for.
        let plan = LessonPlan.plan(size: .medium, depth: .standard, level: "A1",
                                   totalSessions: 7, mode: .lesson, dueCount: 0)
        do {
            let record = try await service.generate(
                spec: LessonSpec(mode: .lesson, size: .medium, depth: .standard,
                                 focus: "asking for and understanding prices",
                                 photoExercises: 0),
                onSpend: { _, cost, _ in spent.add(cost) })

            let elapsed = Int(Date().timeIntervalSince(began))
            let skills = Set(record.lesson.exercises.map { $0.skill.rawValue }).sorted()
            summary.append("\(config.name),\(String(format: "%.4f", spent.total)),"
                           + "\(record.lesson.exercises.count),\(plan.exercises),"
                           + "\(record.lesson.validate().count),\(skills.joined(separator: "|")),"
                           + "\(elapsed)")

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            try encoder.encode(record.lesson)
                .write(to: out.appending(path: "\(config.name).json"))
            print("  \(config.name): $\(String(format: "%.4f", spent.total)), "
                  + "\(record.lesson.exercises.count) exercises, \(elapsed)s — \(record.lesson.title)")
        } catch {
            let elapsed = Int(Date().timeIntervalSince(began))
            summary.append("\(config.name),\(String(format: "%.4f", spent.total)),"
                           + "FAILED,\(plan.exercises),,,\(elapsed)")
            try "\(error)".write(to: out.appending(path: "\(config.name).failure.txt"),
                                 atomically: true, encoding: .utf8)
            print("  \(config.name): FAILED after \(elapsed)s — \(error)")
        }

        // Written after every config, so a run that dies part-way still leaves
        // the results it did pay for.
        try summary.joined(separator: "\n").write(to: out.appending(path: "summary.csv"),
                                                  atomically: true, encoding: .utf8)
    }
    print("  written to \(out.path)")
}


/// A running total written from the subprocess reader thread and read from the
/// test's own.
private final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0
    func add(_ amount: Double) { lock.withLock { value += amount } }
    var total: Double { lock.withLock { value } }
}
