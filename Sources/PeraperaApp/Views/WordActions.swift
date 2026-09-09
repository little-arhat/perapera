import SwiftUI
import PeraperaCore

/// What to do with a word you just pointed at.
///
/// Looking a word up and keeping it are the two things a learner wants from a
/// word they do not know, and both were previously detours: the star saved the
/// whole exercise's answer rather than the word, and a meaning meant copying
/// out to a browser.
struct WordActionsPopover: View {
    let word: String
    let onDismiss: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var gloss = ""
    @State private var justSaved = false

    /// Already in the dictionary? Then its meaning is known, and the useful
    /// offer is to show it rather than to save it again.
    private var existing: SavedItem? {
        model.savedItems.items.first {
            $0.id == SavedItem.identifier(for: word)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RubyText(annotated: word, showFurigana: model.showFurigana, size: 22)

            if let existing, !existing.gloss.isEmpty {
                Text(existing.gloss)
                    .foregroundStyle(palette.emphasizedText)
                if let reading = existing.reading, !reading.isEmpty {
                    Text(reading)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                Label("In your dictionary", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(palette.warning)
            } else if justSaved {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(palette.correct)
            } else {
                // No local meaning, and looking one up costs a call — so this
                // is a field rather than an automatic lookup. The learner types
                // what they find, or saves it blank and fills it in later.
                TextField("Meaning (optional)", text: $gloss)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
            }

            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(word, forType: .string)
                    onDismiss()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .help("Copy for a dictionary lookup elsewhere")

                Button {
                    lookUp()
                } label: {
                    Label("Look up", systemImage: "magnifyingglass")
                }
                .help("Open this word in a dictionary in your browser")

                Spacer()

                if existing == nil, !justSaved {
                    Button("Add") { save() }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                }
            }
            .font(.caption)
        }
        .padding(14)
        .frame(width: 300)
    }

    private func save() {
        model.save(content: word, gloss: gloss, kind: kind, lessonId: nil)
        justSaved = true
    }

    private var kind: SavedItem.Kind {
        let stripped = Furigana.stripped(word)
        if stripped.count == 1, KanaInput.containsKanji(stripped) { return .kanji }
        return stripped.count > 8 ? .phrase : .word
    }

    /// A real dictionary, opened in the browser. Free, and better than any
    /// gloss a model would invent — Jisho gives readings, senses and example
    /// sentences that a one-line translation cannot.
    private func lookUp() {
        let encoded = Furigana.stripped(word)
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        if let url = URL(string: "https://jisho.org/search/\(encoded)") {
            NSWorkspace.shared.open(url)
        }
        onDismiss()
    }
}
