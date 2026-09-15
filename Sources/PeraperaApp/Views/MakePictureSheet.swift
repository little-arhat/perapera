import SwiftUI
import PeraperaCore

/// Make pictures now, of words you are not told.
///
/// The point of a picture is to be read, and a word chosen from a menu has
/// already been read. So the default draws from the dictionary and keeps the
/// word to itself; the saved-word source does the same with your own list.
/// Typing a word is still possible, for when a particular one is wanted.
struct MakePictureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    enum Source: String, CaseIterable {
        case dictionary = "From the dictionary"
        case saved = "A saved word"
        case custom = "Something else"

        /// Whether the word is kept from the learner until the picture is read.
        var isHidden: Bool { self != .custom }
    }

    /// How many at once. Ten is a session; more than that is a bill.
    enum Batch: Int, CaseIterable, Identifiable {
        case one = 1, five = 5, ten = 10
        var id: Int { rawValue }
    }

    @State private var source: Source = .dictionary
    @State private var batch: Batch = .one
    @State private var custom = ""
    @State private var surface: PictureRequest.SurfaceChoice = .surprise
    @AppStorage("picture.scripts") private var scriptsRaw = PictureRequest.Scripts.all.rawValue

    private var scripts: PictureRequest.Scripts {
        PictureRequest.Scripts(rawValue: scriptsRaw)
    }

    private var savedCandidates: [SavedItem] {
        model.savedItems.items.filter { !Furigana.stripped($0.content).isEmpty }
    }

    private var dictionaryPool: [ReadingDrill.Word] {
        PictureRequest.dictionaryPool(model.kanaWords, scripts: scripts)
    }

    /// How many the current settings can produce, capped by the batch size.
    /// Counted rather than assumed so the button is disabled for a real reason.
    private var available: Int {
        switch source {
        case .dictionary:
            return min(batch.rawValue, dictionaryPool.count)
        case .saved:
            let usable = savedCandidates.filter {
                PictureRequest.from($0, surface: .stationSign, scripts: scripts) != nil
            }
            return min(batch.rawValue, usable.count)
        case .custom:
            return PictureRequest.from(text: custom, surface: .stationSign, scripts: scripts) == nil
                ? 0 : 1
        }
    }

    /// Drawn once, when Make is pressed. Drawing in a computed property would
    /// reroll on every redraw and the words would differ from what was counted.
    private func requests() -> [PictureRequest] {
        switch source {
        case .dictionary:
            return PictureRequest.fromDictionary(
                model.kanaWords, count: batch.rawValue, surface: surface, scripts: scripts)
        case .saved:
            return PictureRequest.fromSaved(
                savedCandidates, count: batch.rawValue, surface: surface, scripts: scripts)
        case .custom:
            return PictureRequest.from(text: custom, surface: surface.surface(), scripts: scripts)
                .map { [$0] } ?? []
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
            case .dictionary: dictionaryNote
            case .saved: savedNote
            case .custom: customField
            }

            if source.isHidden { batchPicker }
            surfacePicker
            scriptPicker

            if available == 0, hasChosenSomething {
                // Why the button is disabled, rather than leaving it a mystery.
                Text(unavailableReason)
                    .font(.caption)
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(costNote)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(available > 1 ? "Make \(available)" : "Make it") {
                    let drawn = requests()
                    if !drawn.isEmpty {
                        Task { await model.makePictures(drawn) }
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .disabled(available == 0 || model.isMakingPicture)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var dictionaryNote: some View {
        Text("One of the \(dictionaryPool.count) most frequent words, which you are not "
             + "told. You find out what it says by reading it.")
            .font(.callout)
            .foregroundStyle(palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var savedNote: some View {
        if savedCandidates.isEmpty {
            Label("No saved words yet", systemImage: "star")
                .font(.callout)
                .foregroundStyle(palette.warning)
            Text("Star a word during a lesson with ⇧⌘S, or choose "
                 + "\u{201C}Something else\u{201D} and type one.")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("One of your ^[\(savedCandidates.count) saved word](inflect: true), "
                 + "at random and not named.")
                .font(.callout)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    private var batchPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How many").font(.caption)
                .foregroundStyle(palette.secondaryText)
            Picker("", selection: $batch) {
                ForEach(Batch.allCases) { Text("\($0.rawValue)").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
        }
    }

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
        switch source {
        case .dictionary: true
        case .saved: !savedCandidates.isEmpty
        case .custom: !custom.isEmpty
        }
    }

    /// Named honestly: the usual cause is asking for a form the word has no way
    /// of taking.
    private var unavailableReason: String {
        switch source {
        case .custom where !scripts.contains(.kanji) && KanaInput.containsKanji(custom):
            "That word is written with kanji. Turn Kanji on, or type it in kana."
        case .saved:
            "None of your saved words can be written that way. Words saved "
                + "without a reading can only be shown in kanji."
        default:
            "Nothing to put on the sign with those settings."
        }
    }

    private var costNote: String {
        let each = "The app writes the scene itself, so each picture costs one image — "
            + "about $0.07 — and is checked before you see it. If the writing comes "
            + "out wrong it is discarded."
        return available > 1
            ? each + " \(available) pictures: about $\(String(format: "%.2f", 0.07 * Double(available)))."
            : each
    }

    private var surfacePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Surface", selection: $surface) {
                ForEach(PictureRequest.SurfaceChoice.all, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            Text(surface.summary)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
        }
    }
}
