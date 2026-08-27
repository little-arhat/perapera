import Foundation

/// Running an external command, as a value.
///
/// Kept deliberately small and in one place: this is the only spot in the app
/// that spawns a process, so the failure modes (non-zero exit, stderr, hangs)
/// are handled once rather than at each call site.
enum Subprocess {
    struct Failure: LocalizedError {
        let command: String
        let exitCode: Int32
        let stderr: String

        var errorDescription: String? {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(command) exited \(exitCode)"
                + (detail.isEmpty ? "" : ":\n\(detail)")
        }
    }

    struct Output {
        let stdout: String
        let stderr: String
    }

    /// Runs `executable` with `arguments`, optionally writing `input` to stdin.
    ///
    /// Throws on a non-zero exit rather than returning it: every caller here
    /// treats a failed subprocess as a failed operation, and swallowing the
    /// exit code would turn a known failure into an unknown corruption.
    static func run(
        _ executable: String,
        _ arguments: [String],
        input: Data? = nil,
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.environment = environment ?? ProcessInfo.processInfo.environment

        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        try process.run()

        // Drain both pipes concurrently with writing stdin. A generated lesson
        // can exceed the 64KB pipe buffer; reading only after waitUntilExit
        // would deadlock on exactly the payloads we care about.
        async let outData = readToEnd(outPipe)
        async let errData = readToEnd(errPipe)

        if let input {
            try inPipe.fileHandleForWriting.write(contentsOf: input)
        }
        try? inPipe.fileHandleForWriting.close()

        let (out, err) = try await (outData, errData)
        process.waitUntilExit()

        let stdout = String(decoding: out, as: UTF8.self)
        let stderr = String(decoding: err, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw Failure(
                command: ([executable] + arguments).joined(separator: " "),
                exitCode: process.terminationStatus,
                stderr: stderr.isEmpty ? stdout : stderr
            )
        }
        return Output(stdout: stdout, stderr: stderr)
    }

    /// Runs a command, delivering stdout line by line as it arrives.
    ///
    /// Separate from `run` because the two have genuinely different shapes: one
    /// returns a value, the other reports progress over time. Folding them
    /// together would put a callback on every call site that does not want one.
    static func runStreaming(
        _ executable: String,
        _ arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.environment = environment ?? ProcessInfo.processInfo.environment

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()

        async let errData = readToEnd(errPipe)
        let stdout: String = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var collected = Data()
                var buffer = Data()
                let handle = outPipe.fileHandleForReading
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    collected.append(chunk)
                    buffer.append(chunk)
                    // Newline-delimited JSON: only whole lines are parseable.
                    while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let line = buffer[buffer.startIndex..<newline]
                        buffer = buffer[buffer.index(after: newline)...]
                        if !line.isEmpty {
                            onLine(String(decoding: line, as: UTF8.self))
                        }
                    }
                }
                if !buffer.isEmpty {
                    onLine(String(decoding: buffer, as: UTF8.self))
                }
                continuation.resume(returning: String(decoding: collected, as: UTF8.self))
            }
        }

        let stderr = String(decoding: try await errData, as: UTF8.self)
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw Failure(
                command: ([executable] + arguments).joined(separator: " "),
                exitCode: process.terminationStatus,
                stderr: stderr.isEmpty ? stdout : stderr)
        }
        return Output(stdout: stdout, stderr: stderr)
    }

    private static func readToEnd(_ pipe: Pipe) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Resolves a tool on PATH. GUI apps inherit a minimal PATH that omits
    /// Homebrew, so `claude` must be found rather than assumed.
    static func which(_ tool: String, extraPaths: [String] = []) -> String? {
        let env = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let candidates = extraPaths + env.split(separator: ":").map(String.init)
        for dir in candidates {
            let path = (dir as NSString).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}
