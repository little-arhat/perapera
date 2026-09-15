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
    @State private var justSaved = false
    /// A meaning found without asking anyone, or the answer to asking.
    @State private var found: Glossary.Entry?

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
                // Keyed on the word, not onAppear. Clicking a second word while
                // the popover is open reuses this view rather than making a new
                // one, so onAppear never fires again and the previous word's
                // meaning stays on screen under the new word.
                .task(id: word) {
                    found = model.knownGloss(for: word)
                    justSaved = false
                }

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
            } else if let found {
                Text(found.meaning)
                    .foregroundStyle(palette.emphasizedText)
                if let reading = found.reading, !reading.isEmpty {
                    Text(reading)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                Text(found.source)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            } else {
                // Nothing knows it. Saying so beats a blank field asking the
                // learner to supply the meaning they opened this to find.
                Text("Not in the dictionary — Look up opens JapanDict.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
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
        // Saved with whatever was found, and the reading too. Adding a word
        // with a blank meaning makes a list you have to look up all over again.
        model.save(content: word, gloss: found?.meaning ?? "", kind: kind,
                   lessonId: nil, reading: found?.reading)
        justSaved = true
    }

    private var kind: SavedItem.Kind {
        let stripped = Furigana.stripped(word)
        if stripped.count == 1, KanaInput.containsKanji(stripped) { return .kanji }
        return stripped.count > 8 ? .phrase : .word
    }

    /// A real dictionary, opened in the browser.
    ///
    /// Better than any one-line gloss: JapanDict gives readings, every sense,
    /// inflections and example sentences, which is what you actually want for
    /// the words the bundled dictionary does not carry.
    private func lookUp() {
        JapanDict.open(word)
        onDismiss()
    }
}
