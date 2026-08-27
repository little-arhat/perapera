import SwiftUI
import FluentCore

/// Stars a word or phrase from the current exercise for later practice.
///
/// Opens a small form rather than saving blind: the app cannot know *which*
/// word in a sentence the learner wanted, and guessing would fill the list with
/// noise. The exercise's text is offered as a starting point to edit down.
struct SaveItemButton: View {
    let exercise: Exercise

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    @State private var isPresented = false
    @State private var content = ""
    @State private var gloss = ""
    @State private var kind: SavedItem.Kind = .word

    var body: some View {
        Button {
            content = suggestedContent
            gloss = exercise.explanation.map(Furigana.stripped) ?? ""
            kind = suggestedKind
            isPresented = true
        } label: {
            Label("Save", systemImage: isSaved ? "star.fill" : "star")
                .font(.caption)
                .foregroundStyle(isSaved ? palette.warning : palette.secondaryText)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .help("⇧⌘S — save a word or phrase from this exercise to practice later")
        .popover(isPresented: $isPresented) { form }
    }

    private var isSaved: Bool {
        model.savedItems.contains(suggestedContent)
    }

    /// The answer is usually what is worth keeping; failing that, the prompt.
    private var suggestedContent: String {
        switch exercise.content {
        case let .cloze(accepted), let .digitEntry(accepted):
            accepted.first ?? exercise.prompt
        case let .flashcard(front, _):
            front
        case let .translation(reference), let .freeResponse(reference):
            reference
        case let .multipleChoice(options, index):
            options.indices.contains(index) ? options[index] : exercise.prompt
        case let .reorder(tokens, order):
            Grader.join(order.filter(tokens.indices.contains).map { tokens[$0] })
        case let .matching(pairs):
            pairs.first?.left ?? exercise.prompt
        case let .set(items):
            items.first?.acceptedAnswers.first ?? exercise.prompt
        }
    }

    private var suggestedKind: SavedItem.Kind {
        let stripped = Furigana.stripped(suggestedContent)
        if exercise.skill == .grammar { return .grammar }
        if stripped.count == 1 { return .kanji }
        return stripped.count > 8 ? .phrase : .word
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save for practice")
                .font(.headline)
                .foregroundStyle(palette.emphasizedText)

            VStack(alignment: .leading, spacing: 4) {
                Text("Target language").font(.caption)
                    .foregroundStyle(palette.secondaryText)
                TextField("切符[きっぷ]", text: $content)
                    .textFieldStyle(.roundedBorder)
                Text("Furigana in the form 漢字[かんじ] is kept and shown when readings are on.")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Meaning").font(.caption)
                    .foregroundStyle(palette.secondaryText)
                TextField("ticket", text: $gloss)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("Kind", selection: $kind) {
                ForEach(SavedItem.Kind.allCases, id: \.self) {
                    Text($0.label).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Save") {
                    model.save(content: content, gloss: gloss, kind: kind,
                               lessonId: exercise.id)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
