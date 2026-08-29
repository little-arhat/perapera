import SwiftUI
import FluentCore

/// Renaming a lesson after it exists.
///
/// The point of queuing lessons ahead of time is picking the right one later,
/// which needs a label you can still read a week on. Generation-time naming
/// covers the planned case; this covers the rest — including the lesson you
/// generated without a name and now cannot tell from its neighbour.
struct LabelSheet: View {
    let record: LessonRecord

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var note: String

    init(record: LessonRecord) {
        self.record = record
        _name = State(initialValue: record.name ?? "")
        _note = State(initialValue: record.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Label this lesson")
                .font(.headline)
                .foregroundStyle(palette.emphasizedText)

            // The generated title is shown, not editable: it describes what the
            // lesson actually contains, and overwriting it would lose that.
            Text(record.lesson.title)
                .font(.callout)
                .foregroundStyle(palette.secondaryText)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(palette.secondaryText)
                TextField("plane — counters", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Note").font(.caption).foregroundStyle(palette.secondaryText)
                TextField("do before the Kyoto trip", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    model.label(id: record.id, name: name, note: note)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
