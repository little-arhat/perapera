import AppKit
import Foundation
import PeraperaCore

/// Builds the photographs a recognition exercise needs, and refuses the ones
/// that got the writing wrong.
///
/// Verification is not optional here. A model asked for みなみぐち has been
/// observed drawing みなみりぢち — confidently, in an otherwise convincing sign.
/// A wrong glyph in a reading drill teaches a wrong letterform, which is worse
/// than not practising at all, so an image ships only if a read-back finds the
/// text that was asked for.
///
/// Talks to OpenRouter rather than `claude -p`: image generation is not
/// something the Claude CLI does. That makes this the app's only non-Anthropic
/// dependency, and the reason the key is separate (`OPENROUTER_FLUENT`).
@MainActor
struct ImagePipeline {
    struct Config {
        /// Measured $0.069/image at 100% fidelity. The cheaper 2.5-flash is
        /// $0.039 and renders wrong kana, so it is not an option — see
        /// docs/research/script-recognition.md.
        var generationModel = "google/gemini-3.1-flash-image"
        /// Reads the finished image back. ~$0.0006, against $0.069 to make it:
        /// verification is a rounding error next to a wasted generation.
        var verificationModel = "google/gemini-2.5-flash"
        var apiKey: String
        /// One retry. The failure is stochastic, so a second attempt is worth
        /// it; a third is just paying to be told the same thing.
        var attempts = 2
        var maxImagesPerLesson = 8
    }

    enum Failure: LocalizedError {
        case missingKey
        case generationFailed(String)
        case unreadable(targets: [String], sawInstead: String)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                "No OpenRouter key. Add one in Settings."
            case let .generationFailed(detail):
                "Couldn't generate the image: \(detail)"
            case let .unreadable(targets, saw):
                "The image didn't render the text correctly.\n"
                    + "Wanted: \(targets.joined(separator: " / "))\nGot: \(saw)"
            }
        }
    }

    struct Built {
        let exerciseId: String
        let jpeg: Data
        let costUSD: Double
        let attempts: Int
    }

    let config: Config

    /// Generates and verifies one image. Throws rather than returning a
    /// doubtful picture — a recognition exercise the learner cannot trust is
    /// worse than one exercise fewer.
    func build(
        for exercise: Exercise,
        spec: Exercise.ImageSpec,
        onProgress: @MainActor (String) -> Void = { _ in }
    ) async throws -> Built {
        var spent = 0.0
        var lastSeen = "(nothing legible)"

        for attempt in 1...config.attempts {
            onProgress(
                attempt == 1
                    ? "Making the picture…"
                    : "The text came out wrong — trying once more…")

            let (png, generationCost) = try await generate(spec: spec)
            spent += generationCost

            onProgress("Checking what it actually says…")
            let (transcription, verificationCost) = try await transcribe(png)
            spent += verificationCost

            if matches(targets: spec.targets, in: transcription) {
                let jpeg = try downscale(png)
                return Built(exerciseId: exercise.id, jpeg: jpeg,
                             costUSD: spent, attempts: attempt)
            }
            lastSeen = transcription
        }
        throw Failure.unreadable(targets: spec.targets, sawInstead: lastSeen)
    }

    /// Every requested string must appear. Normalised for width and whitespace
    /// only — a dropped dakuten is exactly the failure being caught.
    private func matches(targets: [String], in transcription: String) -> Bool {
        let haystack = normalize(transcription)
        return targets.allSatisfy { haystack.contains(normalize($0)) }
    }

    private func normalize(_ text: String) -> String {
        let folded = text.applyingTransform(.fullwidthToHalfwidth, reverse: false)
            ?? text
        return folded.filter { !$0.isWhitespace }
    }

    // MARK: - OpenRouter

    private func generate(spec: Exercise.ImageSpec) async throws -> (Data, Double) {
        let instruction = """
        \(spec.scene)

        The image must contain this text, rendered exactly and completely, every \
        character correctly formed:
        \(spec.targets.map { "- \($0)" }.joined(separator: "\n"))

        Photorealistic. No watermarks, no invented extra signage, no real \
        company names or logos.
        """

        let body: [String: Any] = [
            "model": config.generationModel,
            "messages": [["role": "user", "content": instruction]],
            "modalities": ["image", "text"],
            "usage": ["include": true],
        ]
        let json = try await post(body)
        guard
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let images = message["images"] as? [[String: Any]],
            let urlBox = images.first?["image_url"] as? [String: Any],
            let dataURL = urlBox["url"] as? String,
            let comma = dataURL.firstIndex(of: ","),
            let decoded = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
        else {
            throw Failure.generationFailed("no image in the reply")
        }
        return (decoded, cost(of: json))
    }

    private func transcribe(_ png: Data) async throws -> (String, Double) {
        let body: [String: Any] = [
            "model": config.verificationModel,
            "usage": ["include": true],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text":
                        "Transcribe every piece of Japanese text visible in this "
                        + "image, exactly as written, one line per line of text. "
                        + "Include vertical text. Output only the transcriptions."],
                    ["type": "image_url", "image_url": [
                        "url": "data:image/png;base64,\(png.base64EncodedString())",
                    ]],
                ],
            ]],
        ]
        let json = try await post(body)
        let text = ((json["choices"] as? [[String: Any]])?.first?["message"]
            as? [String: Any])?["content"] as? String ?? ""
        return (text, cost(of: json))
    }

    private func cost(of json: [String: Any]) -> Double {
        ((json["usage"] as? [String: Any])?["cost"] as? Double) ?? 0
    }

    private func post(_ body: [String: Any]) async throws -> [String: Any] {
        guard !config.apiKey.isEmpty else { throw Failure.missingKey }
        var request = URLRequest(
            url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure.generationFailed(
                "HTTP \(http.statusCode): \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw Failure.generationFailed("unreadable reply") }
        return json
    }

    /// 2 MB PNG down to ~150 KB JPEG, still legible. Measured; a lesson of
    /// eight would otherwise cost 16 MB for no gain.
    private func downscale(_ png: Data, maxDimension: CGFloat = 1024) throws -> Data {
        guard let image = NSImage(data: png) else { return png }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let target = NSSize(width: image.size.width * scale,
                            height: image.size.height * scale)

        let resized = NSImage(size: target)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target))
        resized.unlockFocus()

        guard
            let tiff = resized.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let jpeg = rep.representation(
                using: .jpeg, properties: [.compressionFactor: 0.72])
        else { return png }
        return jpeg
    }
}
