import SwiftUI
import PeraperaCore

/// A text field that converts romaji to kana as you type, with no IME.
///
/// The learner types latin letters and the field's own text becomes kana. There
/// is no candidate list and no path to kanji, so answering requires recalling
/// the word's *sound* rather than picking its written form out of a menu.
///
/// The field is an ordinary, visible `TextField`. An earlier version hid a
/// transparent field behind a drawn kana overlay; that gave no caret and
/// unreliable focus. Converting the field's own text in place keeps every
/// standard editing behaviour — caret, selection, ⌘Z, arrow keys — working.
/// It is safe because conversion is idempotent over kana: already-converted
/// text passes through untouched on each keystroke.
struct KanaTextField: View {
    /// The graded answer: kana, fully finalized.
    @Binding var text: String
    /// Inside a numbered set, where the explanatory line would repeat per row.
    var compact = false

    @Environment(\.palette) private var palette

    /// What the field shows. Holds kana plus at most a trailing romaji fragment
    /// still waiting for the letter that resolves it.
    ///
    /// A private copy, so it has to be seeded from the binding on appear —
    /// otherwise a restored answer sits in the draft while the field reads
    /// empty, and the learner is shown a blank box for work they did.
    @State private var field = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if compact {
                    TextField("", text: $field)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 17))
                } else {
                    TextField(placeholder, text: $field)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22))
                        .padding(14)
                        .background(palette.surface, in: .rect(cornerRadius: 10))
                }
            }
                .onChange(of: field) { _, new in
                    // Mid-typing, so a trailing "n" is held rather than
                    // committed: otherwise "na" would become んあ, not な.
                    let typed = KanaInput.convert(new, finalizing: false)
                    if typed.display != new {
                        field = typed.display
                    }
                    // What gets graded is the finalized form, where a trailing
                    // "n" has become ん.
                    text = KanaInput.convert(new, finalizing: true).display
                }

            if !compact {
                Text("Romaji becomes kana — no kanji suggestions, on purpose. For katakana or kanji, use your own input method; it passes through untouched.")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    private var placeholder: String { "type romaji — kippu, sanzen…" }
}
