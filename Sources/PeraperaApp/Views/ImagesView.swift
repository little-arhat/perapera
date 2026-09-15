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

    /// How the picture before this one ended, for the card under the field.
    /// A right answer moves straight on, so this is the only confirmation.
    struct Answered: Equatable {
        enum Outcome { case correct, shown, skipped }
        let image: LibraryImage
        let outcome: Outcome
    }

    @State private var mode: Mode = .review
    @State private var current: LibraryImage?
    @State private var typed = ""
    /// A wrong check on this picture. The answer is not shown for it: the
    /// learner tries again, or asks.
    @State private var missed = false
    @State private var revealed = false
    @State private var last: Answered?
    @State private var inspecting: LibraryImage?
    @State private var making = false

    /// Nothing has happened on this picture yet, so it can be replaced by one
    /// just made without losing anything.
    private var untouched: Bool { typed.isEmpty && !missed && !revealed }

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
        // A batch just made is shown as soon as it lands — unless this picture
        // has been started on, in which case it waits for the next advance.
        // Only a rise counts: taking one off the queue also changes the count,
        // and reacting to that would skip straight past the picture just taken.
        .onChange(of: model.unshownPictures.count) { before, after in
            if after > before, mode == .review, untouched { advance() }
        }
        .onChange(of: mode) { _, mode in
            if mode == .review, !model.unshownPictures.isEmpty, untouched { advance() }
        }
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
            Text(model.unshownPictures.isEmpty
                 ? "^[\(images.count) picture](inflect: true)"
                 : "^[\(model.unshownPictures.count) new picture](inflect: true) waiting")
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

                    if revealed {
                        answer(current)
                    } else {
                        prompt(current)
                    }
                    if let last, !revealed { lastCard(last) }
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func prompt(_ image: LibraryImage) -> some View {
        // Plain text, not the kana field: romaji is the natural answer at a
        // keyboard, and the check reads it as such. Kana through an IME still
        // count.
        TextField("Type the reading in romaji", text: $typed)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 17))
            .autocorrectionDisabled()
        if missed {
            Text("Not quite. Try again, or show the answer.")
                .font(.callout)
                .foregroundStyle(palette.wrong)
        }
        HStack {
            Button("Skip") { moveOn(.skipped) }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondaryText)
            Button("Show answer") { revealed = true }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondaryText)
            Spacer()
            Button("Check") { check(image) }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private func answer(_ image: LibraryImage) -> some View {
        AnswerCard(image: image, outcome: nil)
        Button("Next picture") { moveOn(.shown) }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
    }

    private func lastCard(_ last: Answered) -> some View {
        AnswerCard(image: last.image, outcome: last.outcome)
            .padding(.top, 8)
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
        current = model.takeUnshownPicture().map(ImageLibrary.image(for:))
            ?? ImageLibrary.next(from: images, excluding: current?.id)
        typed = ""
        missed = false
        revealed = false
    }

    /// A right answer moves straight on; a wrong one stays, unrevealed, for
    /// another go.
    private func check(_ image: LibraryImage) {
        if PictureRequest.reads(typed, image.accepted) {
            moveOn(.correct)
        } else {
            missed = true
            typed = ""
        }
    }

    private func moveOn(_ outcome: Answered.Outcome) {
        if let current { last = Answered(image: current, outcome: outcome) }
        advance()
    }
}

/// What the sign said: the spelling, its reading in kana and romaji, and the
/// meaning, with the real dictionary a click away.
private struct AnswerCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    let image: LibraryImage
    /// Nil while the picture is still the current one.
    let outcome: ImagesView.Answered.Outcome?

    private var word: String { image.targets.first ?? "" }
    private var reading: String? { PictureRequest.reading(among: image.accepted) }
    private var meaning: String? { model.knownGloss(for: word)?.meaning }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let outcome {
                Image(systemName: icon(outcome))
                    .foregroundStyle(outcome == .correct ? palette.correct : palette.secondaryText)
                    .padding(.top, 4)
            } else {
                Text("It says").font(.caption).foregroundStyle(palette.secondaryText)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    ForEach(image.targets, id: \.self) { target in
                        RubyText(annotated: target, showFurigana: true, size: 22)
                    }
                    if let reading {
                        Text("\(reading)  \(KanaRomaji.romaji(reading))")
                            .font(.callout)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                if let meaning {
                    Text(meaning)
                        .font(.callout)
                        .foregroundStyle(palette.emphasizedText)
                }
            }
            Spacer()
            Button { JapanDict.open(word) } label: {
                Label("JapanDict", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.accent)
            .help("Open in JapanDict")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: .rect(cornerRadius: 10))
    }

    private func icon(_ outcome: ImagesView.Answered.Outcome) -> String {
        switch outcome {
        case .correct: "checkmark.circle.fill"
        case .shown: "eye"
        case .skipped: "forward"
        }
    }
}
