import SwiftUI
import PeraperaCore

/// Make one picture now, of a word you are actually learning.
///
/// The words come from the dictionary rather than being typed from scratch,
/// because a picture of a word you have already met is worth more than a
/// picture of one you invented — and it is the same $0.07 either way.
struct MakePictureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    enum Source: String, CaseIterable { case saved = "A saved word", custom = "Something else" }

    @State private var source: Source = .saved
    @State private var selectedId: String?
    @State private var custom = ""
    @State private var surface: PictureRequest.Surface = .enamelPlate
    /// Let the app choose the surface.
    ///
    /// Text in the street does not announce what it is written on. Always
    /// picking the surface yourself means always picking the one you are
    /// comfortable reading, which trains the surface as much as the word.
    @State private var surprise = false
    /// Rolled once, when Make is pressed. A computed property would reroll on
    /// every redraw and the summary would disagree with what was generated.
    @State private var rolled: PictureRequest.Surface?

    private var chosenSurface: PictureRequest.Surface {
        surprise ? (rolled ?? .stationSign) : surface
    }
    @AppStorage("picture.scripts") private var scriptsRaw = PictureRequest.Scripts.all.rawValue

    private var scripts: PictureRequest.Scripts {
        PictureRequest.Scripts(rawValue: scriptsRaw)
    }

    private var candidates: [SavedItem] {
        model.savedItems.items
            .filter { !Furigana.stripped($0.content).isEmpty }
            .sorted { $0.savedAt > $1.savedAt }
    }

    private var request: PictureRequest? {
        switch source {
        case .saved:
            guard let item = candidates.first(where: { $0.id == selectedId })
            else { return nil }
            return PictureRequest.from(item, surface: chosenSurface, scripts: scripts)
        case .custom:
            return PictureRequest.from(text: custom, surface: chosenSurface, scripts: scripts)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Make a picture")
                .font(.headline)
                .foregroundStyle(palette.emphasizedText)

            Picker("", selection: $source) {
                ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch source {
            case .saved: savedPicker
            case .custom: customField
            }

            surfacePicker
            scriptPicker

            if request == nil, hasChosenSomething {
                // Why the button is disabled, rather than leaving it a mystery.
                Text(unavailableReason)
                    .font(.caption)
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("The app writes the scene itself, so this costs one image — "
                 + "about $0.07 — and is checked before you see it. If the "
                 + "writing comes out wrong it is discarded.")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Make it") {
                    // Roll before reading `request`, which uses the result.
                    if surprise { rolled = PictureRequest.Surface.surprise() }
                    if let request {
                        Task { await model.makePicture(request) }
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .disabled(request == nil || model.isMakingPicture)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            selectedId = selectedId ?? candidates.first?.id
            // Opening on a source with nothing in it looks like a broken
            // dialog: the button is disabled and the reason is a line of small
            // grey text.
            if candidates.isEmpty { source = .custom }
        }
    }

    @ViewBuilder
    private var savedPicker: some View {
        if candidates.isEmpty {
            Label("No saved words yet", systemImage: "star")
                .font(.callout)
                .foregroundStyle(palette.warning)
            Text("Star a word during a lesson with ⇧⌘S, or choose "
                 + "\u{201C}Something else\u{201D} and type one.")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Picker("Word", selection: $selectedId) {
                ForEach(candidates) { item in
                    Text(label(for: item)).tag(Optional(item.id))
                }
            }
            .labelsHidden()
        }
    }

    private func label(for item: SavedItem) -> String {
        let written = Furigana.stripped(item.content)
        return item.gloss.isEmpty ? written : "\(written) — \(item.gloss)"
    }

    @ViewBuilder
    private var customField: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isJapanese {
                // The kana field, not a plain TextField. Japanese typed through
                // the system IME sits as uncommitted marked text and never
                // reaches the binding until Enter is pressed — so the button
                // stayed disabled while the word was visibly on screen. Latin
                // text commits per keystroke, which is why English appeared to
                // work and kana did not.
                KanaTextField(text: $custom)
            } else {
                TextField("exit", text: $custom)
                    .textFieldStyle(.roundedBorder)
            }
            // Long strings are where image models start inventing characters,
            // so the limit is a quality guard rather than tidiness.
            Text("A few characters. Longer text comes out wrong more often.")
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
        }
    }

    private var isJapanese: Bool { model.voiceLanguage == "ja-JP" }

    /// Which writing systems the sign may use.
    ///
    /// A real sign picks one, so these choose what may be *asked for* rather
    /// than what appears together. Turning kanji off is how a learner says "let
    /// me practise kana"; leaving only katakana is how they drill the script
    /// whose words they might otherwise guess from English.
    private var scriptPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Written in").font(.caption)
                .foregroundStyle(palette.secondaryText)
            HStack(spacing: 14) {
                toggle("Kanji", .kanji)
                toggle("Hiragana", .hiragana)
                toggle("Katakana", .katakana)
            }
        }
    }

    private func toggle(_ label: String, _ script: PictureRequest.Scripts) -> some View {
        Toggle(label, isOn: Binding(
            get: { scripts.contains(script) },
            set: { isOn in
                var updated = scripts
                if isOn { updated.insert(script) } else { updated.remove(script) }
                // Never leave nothing selected: an empty set can produce no
                // sign at all, and a control that can disable itself is a trap.
                if !updated.isEmpty { scriptsRaw = updated.rawValue }
            }))
        .toggleStyle(.checkbox)
    }

    private var hasChosenSomething: Bool {
        source == .custom ? !custom.isEmpty : selectedId != nil
    }

    /// Named honestly: the usual cause is asking for a form the word has no way
    /// of taking.
    private var unavailableReason: String {
        if !scripts.contains(.kanji), source == .custom,
           KanaInput.containsKanji(custom) {
            return "That word is written with kanji. Turn Kanji on, or type it in kana."
        }
        if source == .saved,
           let item = candidates.first(where: { $0.id == selectedId }),
           item.reading == nil, !scripts.contains(.kanji) {
            return "No reading saved for this word, so it can only be shown in "
                + "kanji. Turn Kanji on, or add a reading to the entry."
        }
        return "Nothing to put on the sign with those settings."
    }

    private var surfacePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Surface", selection: $surface) {
                ForEach(PictureRequest.surfaces) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            .disabled(surprise)
            Toggle("Surprise me", isOn: $surprise)
                .font(.caption)
                .help("Pick the surface at random. Text in the street does not tell you "
                      + "what it is written on.")
            Text(surprise
                 ? "One of the \(PictureRequest.surfaces.count) at random, chosen when you "
                     + "press Make."
                 : surface.summary)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
        }
    }
}
