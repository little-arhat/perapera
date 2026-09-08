import AVFoundation
import SwiftUI
import FluentCore

struct ArchiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.textScale) private var scale

    @State private var query = ""
    @State private var labelling: LessonRecord?
    @State private var filter: Filter = .all

    /// Why you open the archive: to finish something, or to re-read a grade.
    enum Filter: String, CaseIterable {
        case all = "All"
        case todo = "To do"
        case graded = "Graded"

        var help: String {
            switch self {
            case .all: "Every lesson, finished or not."
            case .todo: "Started or waiting — still owes you work."
            case .graded: "Finished and marked by your teacher."
            }
        }

        func matches(_ record: LessonRecord) -> Bool {
            switch self {
            case .all: true
            case .todo: record.state != .submitted
            case .graded: record.state == .submitted
            }
        }
    }

    private var filtered: [LessonRecord] {
        let scoped = model.records.filter(filter.matches)
        guard !query.isEmpty else { return scoped }
        let needle = query.lowercased()
        return scoped.filter {
            $0.displayTitle.lowercased().contains(needle)
                || $0.lesson.title.lowercased().contains(needle)
                || $0.lesson.focus.lowercased().contains(needle)
                || $0.note?.lowercased().contains(needle) == true
                || $0.feedback?.sessionNotes.lowercased().contains(needle) == true
                || $0.feedback?.overallComment?.lowercased().contains(needle) == true
                || $0.feedback?.graded.contains {
                    $0.comment.lowercased().contains(needle)
                } == true
                || $0.feedback?.errors?.contains {
                    $0.patternId.lowercased().contains(needle)
                        || $0.correctAnswer.lowercased().contains(needle)
                } == true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) {
                        Text($0.rawValue).tag($0).help($0.help)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .help(Filter.allCases.map { "\($0.rawValue) — \($0.help)" }
                    .joined(separator: "\n"))
                TextField("Search lessons, notes, feedback", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            .padding(20)

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Text(model.records.isEmpty ? "No lessons yet." : "Nothing matches that.")
                        .foregroundStyle(palette.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(filtered) { record in
                            Button { model.open(record) } label: {
                                LessonRow(record: record)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Rename…") { labelling = record }
                                Button("Delete", role: .destructive) {
                                    model.delete(id: record.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .frame(maxWidth: scale.width(760))
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .sheet(item: $labelling) { LabelSheet(record: $0) }
    }
}

struct SettingsView: View {
    @State private var openRouterDraft = ""
    @State private var keySaved = false
    @State private var keyError: String?

    @Environment(AppModel.self) private var model
    @Environment(Speech.self) private var speech
    @Environment(\.palette) private var palette

    private var voices: [AVSpeechSynthesisVoice] {
        model.voiceLanguage.map(Speech.voices(for:)) ?? []
    }

    private var onlyBasicVoices: Bool {
        model.voiceLanguage.map(Speech.onlyDefaultQuality(for:)) ?? false
    }

    /// Quality matters more than the name here, so it is part of the label.
    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: "\(voice.name) — premium"
        case .enhanced: "\(voice.name) — enhanced"
        default: voice.name
        }
    }

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Fluent") {
                LabeledContent("Fluent") {
                    Text(model.fluentRoot?.path ?? "not found")
                        .font(.caption.monospaced())
                        .lineLimit(1).truncationMode(.head)
                }
                LabeledContent("Profile") {
                    HStack {
                        Text(model.dataDirectory?.path ?? "no profile yet")
                            .font(.caption.monospaced())
                            .lineLimit(1).truncationMode(.head)
                        if let directory = model.dataDirectory {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(directory.path, forType: .string)
                            }
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([directory])
                            }
                        }
                    }
                }
                // What to paste into .claude/settings.local.json so a terminal
                // tutor session reads the same databases the app does. Without
                // it Fluent silently creates an empty set at its own default.
                if let directory = model.dataDirectory {
                    LabeledContent("Terminal") {
                        Button("Copy FLUENT_DATA_DIR setting") {
                            let json = """
                                "env": { "FLUENT_DATA_DIR": "\(directory.path)" }
                                """
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(json, forType: .string)
                        }
                    }
                }
            }

            Section("OpenRouter") {
                // Only needed for generated photographs. Stored in the Keychain,
                // so it is encrypted at rest and scoped to this app rather than
                // readable by anything running as the learner.
                SecureField("API key", text: $openRouterDraft)
                    .onSubmit { saveKey() }
                HStack {
                    Button("Save key") { saveKey() }
                        .disabled(openRouterDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text(keyStatus)
                        .font(.caption)
                        .foregroundStyle(keySaved ? palette.correct : palette.secondaryText)
                }
            }

            Section("Reading") {
                Toggle("Highlight the word under the pointer", isOn: $model.highlightWords)
                    .help("Japanese has no spaces, so seeing where a word ends is a "
                          + "reading aid rather than a convenience. Click copies it.")
                Toggle("Colour particles", isOn: $model.tintParticles)
                    .help("は, を, に, で and the rest in a separate colour. They are "
                          + "short and unstressed and carry the whole grammatical "
                          + "structure, which is where sentences get lost.")
                Toggle("Show readings by default", isOn: $model.showFurigana)
                    .help("Off by default: a learner who always sees the reading "
                          + "never learns to read the kanji. ⌘F toggles per screen.")
            }

            Section("Speech") {
                Picker("Voice", selection: $model.voiceIdentifier) {
                    Text("Best installed").tag("")
                    ForEach(voices, id: \.identifier) { voice in
                        Text(voiceLabel(voice)).tag(voice.identifier)
                    }
                }
                .disabled(voices.isEmpty)

                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: $model.speechRate, in: 0.25...0.55) {
                        Text("Slow speed")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise")
                    } maximumValueLabel: {
                        Image(systemName: "hare")
                    }
                    // The scale is misleading enough to be worth spelling out:
                    // 0.375 and 0.5 sound identical, 0.30 clearly does not.
                    Text("Used by Play slowly. The scale is uneven — small moves near the top do almost nothing.")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }

                Button("Preview") {
                    speech.speak("さんぜんはっぴゃくえんです。",
                                 language: model.voiceLanguage,
                                 rate: Float(model.speechRate),
                                 voiceIdentifier: model.voiceIdentifier.nilWhenEmpty)
                }

                if onlyBasicVoices {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Only the basic voice is installed",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(palette.warning)
                        Text(Speech.betterVoicesHint)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Spoken Content settings") {
                            Speech.openVoiceSettings()
                        }
                    }
                }
            }

            Section("Claude") {
                TextField("Path to `claude`", text: $model.claudePath)
                    .font(.caption.monospaced())
                Picker("Model", selection: $model.model) {
                    Text("Opus").tag("opus")
                    Text("Sonnet").tag("sonnet")
                    Text("Haiku").tag("haiku")
                }
                Text("Opus generates and grades by default. Generation is the high-volume call, so switching it to Sonnet is the main cost lever.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onChange(of: model.claudePath) { model.rebuildServices() }
        .onChange(of: model.model) { model.rebuildServices() }
    }

    private var keyStatus: String {
        if let keyError { return keyError }
        if keySaved { return "Saved to the Keychain." }
        return model.canGenerateImages ? "A key is stored." : "No key yet — photographs are off."
    }

    private func saveKey() {
        do {
            try Secrets.setOpenRouter(openRouterDraft)
            openRouterDraft = ""
            keyError = nil
            keySaved = true
            model.rebuildServices()
        } catch {
            keyError = error.localizedDescription
            keySaved = false
        }
    }

}
