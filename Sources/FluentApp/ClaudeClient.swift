import Foundation
import FluentCore

/// Calls `claude -p` as a pure function: a prompt goes in, schema-validated
/// JSON comes out.
///
/// The app never lets the model touch its databases. Everything the teacher
/// produces is a value that the app validates before acting on, which is what
/// makes a bad generation a retry rather than a corruption.
@MainActor
final class ClaudeClient {
    struct Config {
        var executable: String
        var model: String = "opus"
        /// A ceiling per call, so a runaway generation fails loudly instead of
        /// quietly costing money.
        var maxBudgetUSD: Double = 2.0
        var workingDirectory: URL
    }

    enum Failure: LocalizedError {
        case claudeNotFound
        case emptyResponse
        case malformedJSON(underlying: Error, raw: String)

        var errorDescription: String? {
            switch self {
            case .claudeNotFound:
                "Couldn't find the `claude` executable. Set its path in Settings."
            case .emptyResponse:
                "Claude returned nothing."
            case let .malformedJSON(error, raw):
                "Claude's reply didn't match the schema: \(error.localizedDescription)\n\n\(raw.prefix(600))"
            }
        }
    }

    private let config: Config

    init(config: Config) {
        self.config = config
    }

    /// Asks for a value of type `T`, validated against `schema`.
    ///
    /// Retries once on malformed output, because the failure it corrects is
    /// stochastic. It does NOT retry other failures: a missing executable or a
    /// budget refusal will fail identically the second time, and retrying them
    /// would only hide the real cause.
    func request<T: Decodable>(
        _ type: T.Type,
        prompt: String,
        schema: String,
        progress: (@Sendable (Progress) -> Void)? = nil,
        onSpend: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> T {
        do {
            return try await attempt(type, prompt: prompt, schema: schema,
                                     progress: progress, onSpend: onSpend)
        } catch Failure.malformedJSON {
            progress?(Progress(phase: .retrying, text: "", thinkingTokens: 0))
            // A retry is charged too, so its cost is reported separately rather
            // than replacing the first attempt's.
            return try await attempt(type, prompt: prompt, schema: schema,
                                     progress: progress, onSpend: onSpend)
        }
    }

    /// What the model is doing right now.
    ///
    /// A spinner for a 40-second wait tells the learner nothing, and a wait with
    /// no signal reads as a hang. The text is the answer as it is being written,
    /// which is both honest progress and mildly interesting to watch.
    struct Progress: Sendable {
        enum Phase: Sendable {
            case starting, thinking, writing, retrying, finishing

            var label: String {
                switch self {
                case .starting: "Connecting…"
                case .thinking: "Thinking…"
                case .writing: "Writing…"
                case .retrying: "That reply didn't fit the format — asking again…"
                case .finishing: "Finishing up…"
                }
            }
        }

        let phase: Phase
        /// The answer so far.
        let text: String
        let thinkingTokens: Int
    }

    private func attempt<T: Decodable>(
        _ type: T.Type,
        prompt: String,
        schema: String,
        progress: (@Sendable (Progress) -> Void)?,
        onSpend: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> T {
        let collector = StreamCollector(report: progress)
        let result = try await Subprocess.runStreaming(
            config.executable,
            [
                "-p", prompt,
                "--model", config.model,
                // Streamed so the wait can be shown rather than spun through.
                "--output-format", "stream-json",
                "--verbose",
                "--include-partial-messages",
                "--json-schema", schema,
                "--max-budget-usd", String(config.maxBudgetUSD),
                // No tools: this call is a pure transformation, and a teacher
                // that could edit files would defeat the point of the app owning
                // its own writes.
                "--allowedTools", "",
            ],
            currentDirectory: config.workingDirectory,
            onLine: { line in collector.consume(line) }
        )

        progress?(Progress(phase: .finishing, text: collector.answer, thinkingTokens: 0))
        if let cost = collector.cost, cost > 0 {
            onSpend?(cost, config.model)
        }

        // The last `result` event carries the finished value; the accumulated
        // text deltas are the fallback if the envelope shape ever changes.
        let raw = collector.result ?? collector.answer
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            _ = result
            throw Failure.emptyResponse
        }

        let payload = try unwrapEnvelope(raw)
        do {
            return try JSONDecoder().decode(T.self, from: payload)
        } catch {
            throw Failure.malformedJSON(underlying: error, raw: raw)
        }
    }

    /// Pulls the structured answer out of the CLI envelope. Falls back to
    /// treating the whole reply as the answer, so a future envelope change
    /// degrades to "still works" rather than "breaks".
    private func unwrapEnvelope(_ raw: String) throws -> Data {
        let data = Data(stripFence(raw).utf8)
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return data
        }
        if let result = object["result"] {
            if let string = result as? String {
                return Data(stripFence(string).utf8)  // carried as a JSON string
            }
            return try JSONSerialization.data(withJSONObject: result)
        }
        return data
    }

    /// Removes a ```json fence. Models add one even under a schema, and a fenced
    /// reply is correct content wrapped in the wrong packaging -- worth
    /// unwrapping rather than paying for a retry.
    private func stripFence(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else { return text }
        if let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }
        if let fence = text.range(of: "```", options: .backwards) {
            text = String(text[..<fence.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Turns the CLI's newline-delimited event stream into progress and a result.
///
/// Lives outside `ClaudeClient` because it is called from the subprocess's
/// reader thread, not the main actor. It owns a lock rather than an actor so a
/// line can be consumed synchronously as it arrives.
final class StreamCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private var thinkingTokens = 0
    private var finalResult: String?
    private var totalCost: Double?
    private let report: (@Sendable (ClaudeClient.Progress) -> Void)?

    init(report: (@Sendable (ClaudeClient.Progress) -> Void)?) {
        self.report = report
    }

    var answer: String { lock.withLock { text } }
    var result: String? { lock.withLock { finalResult } }
    var cost: Double? { lock.withLock { totalCost } }

    func consume(_ line: String) {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String
        else { return }

        switch type {
        case "stream_event":
            handleStreamEvent(event["event"] as? [String: Any])
        case "result":
            // The finished, schema-validated value, and what it cost.
            if let value = event["result"] as? String {
                lock.withLock { finalResult = value }
            }
            if let spent = event["total_cost_usd"] as? Double {
                lock.withLock { totalCost = spent }
            }
        default:
            break
        }
    }

    private func handleStreamEvent(_ event: [String: Any]?) {
        guard let event,
              event["type"] as? String == "content_block_delta",
              let delta = event["delta"] as? [String: Any]
        else { return }

        switch delta["type"] as? String {
        case "text_delta":
            guard let chunk = delta["text"] as? String else { return }
            let (snapshot, tokens) = lock.withLock { () -> (String, Int) in
                text += chunk
                return (text, thinkingTokens)
            }
            report?(.init(phase: .writing, text: snapshot, thinkingTokens: tokens))

        case "thinking_delta":
            let estimated = delta["estimated_tokens"] as? Int ?? 0
            let tokens = lock.withLock { () -> Int in
                thinkingTokens += estimated
                return thinkingTokens
            }
            report?(.init(phase: .thinking, text: "", thinkingTokens: tokens))

        default:
            break
        }
    }
}
