import SwiftUI
import FluentCore

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
            return PictureRequest.from(item, surface: surface)
        case .custom:
            return PictureRequest.from(text: custom, surface: surface)
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
        .onAppear { selectedId = selectedId ?? candidates.first?.id }
    }

    @ViewBuilder
    private var savedPicker: some View {
        if candidates.isEmpty {
            Text("No saved words yet — star one during a lesson, or type "
                 + "something below instead.")
                .font(.callout)
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

    private var customField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("出口", text: $custom)
                .textFieldStyle(.roundedBorder)
            // Long strings are where image models start inventing characters,
            // so the limit is a quality guard rather than tidiness.
            Text("A few characters. Longer text comes out wrong more often.")
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
        }
    }

    private var surfacePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Surface", selection: $surface) {
                ForEach(PictureRequest.surfaces) { option in
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
