import SwiftUI
import PeraperaCore

/// Everything the app has photographed, to browse or to be tested on.
///
/// These pictures cost about $0.07 each and were previously seen once, inside
/// the lesson that made them. Nothing about a sign goes stale, so re-reading
/// one a month later is free practice at exactly the skill it was made for.
struct ImagesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    enum Mode: String, CaseIterable { case review = "Review", browse = "All" }

    @State private var mode: Mode = .review
    @State private var current: LibraryImage?
    @State private var typed = ""
    @State private var verdict: Verdict?
    @State private var inspecting: LibraryImage?
    @State private var making = false

    private var images: [LibraryImage] { model.imageLibrary }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if images.isEmpty {
                empty
            } else {
                switch mode {
                case .review: review
                case .browse: contactSheet
                }
            }
        }
        .onAppear(perform: pickIfNeeded)
        .sheet(item: $inspecting) { detail($0) }
        .sheet(isPresented: $making) { MakePictureSheet() }
    }

    private var header: some View {
        HStack {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)

            Spacer()
            Text("^[\(images.count) picture](inflect: true)")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)

            Button { making = true } label: {
                Label("Make one", systemImage: "camera")
            }
            .disabled(!model.canGenerateImages || model.isMakingPicture)
            .help(model.canGenerateImages
                  ? "Generate a picture of a word you are learning — about $0.07."
                  : "Needs an OpenRouter key in Settings")
        }
        .padding(20)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundStyle(palette.secondaryText)
            Text("No photographs yet")
                .font(.headline)
                .foregroundStyle(palette.emphasizedText)
            Text("Generate a lesson with photographs turned on, or make one now "
                 + "from a word you have saved.")
                .font(.callout)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button { making = true } label: {
                Label("Make one", systemImage: "camera")
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .disabled(!model.canGenerateImages)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Review

    @ViewBuilder
    private var review: some View {
        if let current {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let url = model.imageURL(lessonId: current.lessonId,
                                                fileName: current.fileName),
                       let picture = NSImage(contentsOf: url) {
                        Image(nsImage: picture)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 420)
                            .clipShape(.rect(cornerRadius: 12))
                    }

                    Text(current.question ?? "What does it say?")
                        .font(.system(size: 19))
                        .foregroundStyle(palette.emphasizedText)

                    if verdict == nil {
                        KanaTextField(text: $typed)
                        HStack {
                            Button("Skip") { reveal(scoring: false) }
                                .buttonStyle(.plain)
                                .foregroundStyle(palette.secondaryText)
                            Spacer()
                            Button("Check") { reveal(scoring: true) }
                                .buttonStyle(.borderedProminent)
                                .tint(palette.accent)
                                .keyboardShortcut(.return, modifiers: [])
                                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .controlSize(.large)
                    } else {
                        outcome(current)
                    }
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func outcome(_ image: LibraryImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let verdict {
                Label(verdict.isCorrect ? "Correct" : "Not quite",
                      systemImage: verdict.isCorrect
                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(verdict.isCorrect ? palette.correct : palette.wrong)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("It says").font(.caption).foregroundStyle(palette.secondaryText)
                ForEach(image.targets, id: \.self) { target in
                    RubyText(annotated: target, showFurigana: true, size: 22)
                }
                Text(image.accepted.joined(separator: " / "))
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: .rect(cornerRadius: 10))

            Button("Next picture") { advance() }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    // MARK: - Contact sheet

    private var contactSheet: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: 14)],
                spacing: 14
            ) {
                ForEach(images) { image in
                    Button { inspecting = image } label: { thumbnail(image) }
                        .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
    }

    private func thumbnail(_ image: LibraryImage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = model.imageURL(lessonId: image.lessonId,
                                        fileName: image.fileName),
               let picture = NSImage(contentsOf: url) {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 130)
                    .clipped()
                    .clipShape(.rect(cornerRadius: 8))
            }
            // The transcription is the point of the sheet: it is how you find
            // the picture you half remember.
            ForEach(image.targets, id: \.self) { target in
                RubyText(annotated: target, showFurigana: model.showFurigana, size: 15)
            }
            Text(image.lessonTitle)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .padding(10)
        .background(palette.surface, in: .rect(cornerRadius: 10))
    }

    private func detail(_ image: LibraryImage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url = model.imageURL(lessonId: image.lessonId,
                                        fileName: image.fileName),
               let picture = NSImage(contentsOf: url) {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 720, maxHeight: 520)
            }
            ForEach(image.targets, id: \.self) { target in
                RubyText(annotated: target, showFurigana: true, size: 22)
            }
            Text(image.accepted.joined(separator: " / "))
                .foregroundStyle(palette.secondaryText)
            HStack {
                Text(image.lessonTitle)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Button("Done") { inspecting = nil }
            }
        }
        .padding(20)
        .frame(maxWidth: 760)
    }

    // MARK: - Actions

    private func pickIfNeeded() {
        if current == nil { advance() }
    }

    private func advance() {
        current = ImageLibrary.next(from: images, excluding: current?.id)
        typed = ""
        verdict = nil
    }

    /// Graded exactly as the lesson would, so the answer that passes here is
    /// the answer that passes there.
    private func reveal(scoring: Bool) {
        guard let current else { return }
        verdict = scoring
            ? Grader.gradeText(
                accepted: current.accepted, answer: .text(typed),
                prompt: current.question ?? "", allowDeferral: false).verdict
            : Verdict(isCorrect: false, score: 0,
                      correctVersion: current.accepted.first ?? "")
    }
}
