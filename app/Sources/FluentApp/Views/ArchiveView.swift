import AVFoundation
import SwiftUI
import FluentCore

struct ArchiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.textScale) private var scale

    @State private var query = ""
    @State private var labelling: LessonRecord?

    private var filtered: [LessonRecord] {
        guard !query.isEmpty else { return model.records }
        let needle = query.lowercased()
        return model.records.filter {
            $0.displayTitle.lowercased().contains(needle)
                || $0.lesson.title.lowercased().contains(needle)
                || $0.lesson.focus.lowercased().contains(needle)
                || $0.note?.lowercased().contains(needle) == true
                || $0.feedback?.sessionNotes.lowercased().contains(needle) == true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { model.screen = .home } label: {
                    Label("Home", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondaryText)
                Spacer()
                TextField("Search lessons", text: $query)
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
                LabeledContent("Repo") {
                    HStack {
                        Text(model.pluginRoot.path)
                            .font(.caption.monospaced())
                            .lineLimit(1).truncationMode(.head)
                        Button("Choose…") { chooseRepo() }
                    }
                }
                LabeledContent("Data") {
                    Text(model.dataDirectory.path)
                        .font(.caption.monospaced())
                        .lineLimit(1).truncationMode(.head)
                }
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

    private func chooseRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.pluginRoot = url
            model.rebuildServices()
            Task { await model.refresh() }
        }
    }
}
