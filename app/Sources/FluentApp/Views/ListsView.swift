import SwiftUI
import FluentCore

/// The learner's saved words, kanji, and phrases.
///
/// Not a second scheduler. Items here are on their way into Fluent's spaced
/// repetition — "Pending" means starred but not yet handed over, which happens
/// when the lesson they came from is finished. Practising a list is deliberate
/// drilling on top of that schedule, never instead of it.
struct ListsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.textScale) private var scale

    @State private var selection: Set<String> = []
    @State private var filter: SavedItem.Kind?
    @State private var size: LessonSpec.Size = .small
    @State private var depth: LessonSpec.Depth = .drill
    @State private var drilling = false

    private var items: [SavedItem] {
        let all = model.savedItems.items.sorted { $0.savedAt > $1.savedAt }
        guard let filter else { return all }
        return all.filter { $0.kind == filter }
    }

    private var chosen: [SavedItem] {
        selection.isEmpty ? items : items.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if model.savedItems.items.isEmpty {
                empty
            } else {
                list
                practiceBar
            }
        }
    }

    private var header: some View {
        HStack {
            Spacer()

            Picker("", selection: $filter) {
                Text("All").tag(SavedItem.Kind?.none)
                ForEach(SavedItem.Kind.allCases, id: \.self) {
                    Text($0.label).tag(SavedItem.Kind?.some($0))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 340)

            FuriganaToggle(isOn: Binding(
                get: { model.showFurigana },
                set: { model.showFurigana = $0 }))
        }
        .padding(20)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "star")
                .font(.system(size: 34))
                .foregroundStyle(palette.secondaryText)
            Text("Nothing saved yet")
                .font(.headline)
                .foregroundStyle(palette.emphasizedText)
            Text("While doing a lesson, press ⇧⌘S — or the star beside a question — to keep a word, kanji, or phrase for later practice.")
                .font(.callout)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(items) { item in
                    row(item)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: scale.width(820))
            .frame(maxWidth: .infinity)
        }
    }

    private func row(_ item: SavedItem) -> some View {
        HStack(spacing: 12) {
            Button {
                if selection.contains(item.id) { selection.remove(item.id) }
                else { selection.insert(item.id) }
            } label: {
                Image(systemName: selection.contains(item.id)
                      ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection.contains(item.id)
                                     ? palette.accent : palette.secondaryText)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                RubyText(annotated: item.content,
                         showFurigana: model.showFurigana, size: 19)
                    .foregroundStyle(palette.emphasizedText)
                if !item.gloss.isEmpty {
                    Text(item.gloss)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                        .selectableIf(scale.selectable)
                }
                if let example = item.example, !example.isEmpty {
                    RubyText(annotated: example,
                             showFurigana: model.showFurigana, size: 13)
                        .foregroundStyle(palette.secondaryText)
                }
            }

            Spacer()

            Text(item.kind.label)
                .font(.caption2)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(palette.background, in: .capsule)
                .foregroundStyle(palette.secondaryText)

            // "Pending" is a real distinction: until it is promoted, Fluent has
            // never seen this item and it has no review schedule.
            // How the drills have gone, when there have been any.
            if let accuracy = item.accuracy {
                Text("\(item.correct)/\(item.attempts)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(accuracy >= 0.8 ? palette.correct
                                     : accuracy >= 0.5 ? palette.warning : palette.wrong)
                    .frame(width: 36, alignment: .trailing)
            }

            Text(item.isPending ? "pending" : "scheduled")
                .font(.caption2)
                .foregroundStyle(item.isPending ? palette.warning : palette.correct)
                .frame(width: 66, alignment: .trailing)

            Button {
                model.unsave(id: item.id)
                selection.remove(item.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(palette.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(palette.surface, in: .rect(cornerRadius: 10))
    }

    private var practiceBar: some View {
        HStack(spacing: 12) {
            Text(selection.isEmpty
                 ? "^[\(items.count) item](inflect: true) — all of them"
                 : "\(selection.count) selected")
                .font(.callout)
                .foregroundStyle(palette.secondaryText)

            if !selection.isEmpty {
                Button("Clear") { selection.removeAll() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()

            Picker("", selection: $size) {
                ForEach(LessonSpec.Size.allCases, id: \.self) {
                    Text($0.label).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
            .help("How many distinct topics the lesson covers.")

            Picker("", selection: $depth) {
                ForEach(LessonSpec.Depth.allCases, id: \.self) {
                    Text($0.label).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .help("How many times each topic is practised.")

            // Free and instant, so it comes first: drilling what is already
            // saved costs nothing, while generating a lesson costs a call.
            Button {
                drilling = true
            } label: {
                Label("Drill", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.bordered)
            .disabled(chosen.isEmpty)
            .help("Translate these words both ways. No network, no cost.")

            Button {
                Task { await model.practice(items: chosen, size: size, depth: depth) }
            } label: {
                Label("Practice these", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .disabled(chosen.isEmpty || model.isGenerating)
        }
        .controlSize(.large)
        .padding(20)
        .background(palette.surface)
        .sheet(isPresented: $drilling) {
            DrillView(items: model.savedItems.drillCandidates(limit: 10)) { outcomes in
                model.recordDrill(outcomes)
            }
        }
    }
}
