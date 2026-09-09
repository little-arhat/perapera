import AVFoundation
import AppKit
import Observation

/// Speaks target-language text aloud.
///
/// macOS ships Japanese voices, so this needs no API, no network, and no key --
/// which is what lets listening exercises work on a plane. It is the only way
/// the app can practice the skill Fluent tracks but a terminal cannot.
@MainActor
@Observable
final class Speech {
    /// Playback speeds, measured rather than guessed.
    ///
    /// `AVSpeechUtteranceDefaultSpeechRate` is 0.5, and the scale is far from
    /// linear: on a 4.2 s Japanese sentence, 0.375 lands at 4.6 s -- an 8%
    /// difference nobody can hear. 0.3 lands at 5.6 s, which is audibly a
    /// different reading. So "slow" has to reach well below the default to mean
    /// anything.
    public enum Rate {
        static let slow: Float = 0.30
        static let natural: Float = AVSpeechUtteranceDefaultSpeechRate  // 0.5
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let monitor = Monitor()

    private(set) var isSpeaking = false

    init() {
        monitor.onChange = { [weak self] speaking in
            self?.isSpeaking = speaking
        }
        synthesizer.delegate = monitor
    }

    /// BCP-47 language for the learner's target language. Falls back to the
    /// system default voice when we have no mapping, which degrades to
    /// "reads it with the wrong accent" rather than silence.
    static func voiceCode(for targetLanguage: String) -> String? {
        switch targetLanguage.lowercased() {
        case "japanese": "ja-JP"
        case "spanish": "es-ES"
        case "french": "fr-FR"
        case "german": "de-DE"
        case "italian": "it-IT"
        case "dutch": "nl-NL"
        case "portuguese": "pt-PT"
        case "korean": "ko-KR"
        case "chinese", "mandarin": "zh-CN"
        case "russian": "ru-RU"
        case "arabic": "ar-SA"
        case "english": "en-US"
        default: nil
        }
    }

    /// The best installed voice for a language.
    ///
    /// macOS ships every language with a `.default` voice and offers higher
    /// quality ones as downloads (System Settings → Accessibility → Spoken
    /// Content). Picking the best installed one means the app improves the
    /// moment a better voice is added, with no code change.
    static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
        guard !candidates.isEmpty else {
            return AVSpeechSynthesisVoice(language: language)
        }
        return candidates.max { a, b in a.quality.rawValue < b.quality.rawValue }
    }

    /// Every installed voice for a language, best first — for a voice picker.
    static func voices(for language: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .sorted {
                $0.quality.rawValue == $1.quality.rawValue
                    ? $0.name < $1.name
                    : $0.quality.rawValue > $1.quality.rawValue
            }
    }

    /// True when every installed voice for a language is the basic one.
    ///
    /// Worth saying out loud. macOS ships only `.default` voices; the better
    /// ones are a free download most people never discover, and without a
    /// prompt the learner concludes the robotic reading is as good as the app
    /// gets — and quietly trusts the listening practice less.
    static func onlyDefaultQuality(for language: String) -> Bool {
        let installed = voices(for: language)
        return !installed.isEmpty && installed.allSatisfy { $0.quality == .default }
    }

    /// Where to get better ones. Shown, not just linked, because the path is
    /// four levels deep in System Settings.
    static let betterVoicesHint =
        "System Settings → Accessibility → Spoken Content → System Voice → "
        + "Manage Voices. Kyoko (Enhanced) is the one worth downloading."

    static func openVoiceSettings() {
        // Deep link straight to Spoken Content; the pane is hard to find.
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.universalaccess"
                + "?SpeakableItems")
        if let url { NSWorkspace.shared.open(url) }
    }

    func speak(
        _ text: String,
        language: String?,
        rate: Float = Rate.slow,
        voiceIdentifier: String? = nil
    ) {
        guard !text.isEmpty else { return }
        stop()

        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier,
           let chosen = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = chosen
        } else if let language {
            utterance.voice = Self.bestVoice(for: language)
        }
        utterance.rate = rate
        // A beat of silence before speech: without it the first mora is often
        // clipped by the audio device waking up, and the first mora is exactly
        // where the sound changes live (はっ, さんぜ).
        utterance.preUtteranceDelay = 0.15

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    static func hasVoice(for language: String) -> Bool {
        bestVoice(for: language) != nil
    }

    /// `isSpeaking` is not true the instant `speak` returns -- synthesis starts
    /// asynchronously -- so polling it reports "finished" immediately. The
    /// delegate is the only accurate signal.
    private final class Monitor: NSObject, AVSpeechSynthesizerDelegate {
        var onChange: ((Bool) -> Void)?

        func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
            Task { @MainActor in self.onChange?(true) }
        }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
            Task { @MainActor in self.onChange?(false) }
        }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
            Task { @MainActor in self.onChange?(false) }
        }
    }
}
