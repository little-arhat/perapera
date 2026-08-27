import SwiftUI
import FluentCore

/// The play control for an exercise that carries audio.
///
/// For a listening exercise the transcript starts hidden: showing it would turn
/// a listening test into a reading test, which is the failure mode that makes
/// "listening practice" in a text interface worthless. The learner can still
/// reveal it, but only deliberately, and only after hearing it.
struct AudioPromptView: View {
    let text: String
    let language: String?
    let isListeningExercise: Bool

    @Environment(\.palette) private var palette
    @Environment(Speech.self) private var speech

    @State private var hasPlayed = false
    @State private var showTranscript = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    hasPlayed = true
                    speech.speak(text, language: language, rate: Speech.Rate.slow)
                } label: {
                    Label(hasPlayed ? "Play again" : "Play slowly",
                          systemImage: "speaker.wave.2.fill")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .controlSize(.large)
                .keyboardShortcut("p", modifiers: [.command])

                Button {
                    hasPlayed = true
                    speech.speak(text, language: language, rate: Speech.Rate.natural)
                } label: {
                    Label("Natural speed", systemImage: "hare")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if unavailable {
                    Label("No voice installed for this language",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(palette.warning)
                }
            }

            if isListeningExercise {
                if showTranscript {
                    Text(text)
                        .font(.system(size: 20))
                        .foregroundStyle(palette.emphasizedText)
                        .textSelection(.enabled)
                } else {
                    Button("Show transcript") { showTranscript = true }
                        .buttonStyle(.plain)
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            } else {
                Text(text)
                    .font(.system(size: 20))
                    .foregroundStyle(palette.emphasizedText)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: .rect(cornerRadius: 10))
    }

    private var unavailable: Bool {
        guard let language else { return false }
        return !Speech.hasVoice(for: language)
    }
}
