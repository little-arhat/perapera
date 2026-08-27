import SwiftUI
import FluentCore

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    @State private var size: LessonSpec.Size = .medium
    @State private var depth: LessonSpec.Depth = .standard
    @State private var focus = ""
    @State private var showUnreadable = false

    private var pending: [LessonRecord] {
        model.records.filter { $0.state != .submitted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                generator
                if !pending.isEmpty { pendingSection }
                footer
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let snapshot = model.snapshot {
                let learner = snapshot.databases.learner_profile.learner
                Text("\(learner.name) · \(learner.target_language)")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(palette.emphasizedText)

                HStack(spacing: 16) {
                    Label("\(snapshot.databases.learner_profile.current_streak_days) day streak",
                          systemImage: "flame.fill")
                        .foregroundStyle(snapshot.computed.streak_active ? palette.critical : palette.secondaryText)
                    Label("\(snapshot.computed.due_reviews_count) due",
                          systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(snapshot.computed.due_reviews_count > 0 ? palette.review : palette.secondaryText)
                    Label("\(learner.current_level) → \(learner.target_level)",
                          systemImage: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(palette.secondaryText)
                }
                .font(.callout)
            } else {
                Text("Loading…").foregroundStyle(palette.secondaryText)
            }
        }
    }

    private var generator: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Two dimensions, deliberately separate: how many points, and how
            // many repetitions of each.
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How much").font(.caption)
                        .foregroundStyle(palette.secondaryText)
                    Picker("Size", selection: $size) {
                        ForEach(LessonSpec.Size.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repetition").font(.caption)
                        .foregroundStyle(palette.secondaryText)
                    Picker("Depth", selection: $depth) {
                        ForEach(LessonSpec.Depth.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            Text("\(size.label) covers more ground; \(depth.label.lowercased()) repeats each point \(depth.itemsPerSet) times.")
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)

            TextField("Focus (optional) — e.g. counters, train station, kanji reading",
                      text: $focus)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button {
                    Task { await model.generate(mode: .lesson, size: size, depth: depth, focus: focus) }
                } label: {
                    Label("Generate Lesson", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)

                Button {
                    Task { await model.generate(mode: .review, size: size, depth: depth, focus: focus) }
                } label: {
                    Label("Generate Review", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.review)
                .disabled(model.snapshot?.computed.due_reviews_count == 0)
            }
            .controlSize(.large)
            .disabled(model.isGenerating)

            if model.snapshot?.computed.due_reviews_count == 0 {
                Text("Nothing is due for review right now — generate a lesson instead.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(20)
        .background(palette.surface, in: .rect(cornerRadius: 12))
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ready to do")
                .font(.headline)
                .foregroundStyle(palette.emphasizedText)

            Text("Generated lessons stay here until you finish them. You can do them offline; only **Finish lesson** needs a connection.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)

            ForEach(pending) { record in
                Button { model.open(record) } label: {
                    LessonRow(record: record)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button("Archive") { model.screen = .archive }
            Button {
                model.screen = .lists
            } label: {
                if model.savedItems.pending.isEmpty {
                    Text("Saved (\(model.savedItems.items.count))")
                } else {
                    Label("Saved (\(model.savedItems.items.count))",
                          systemImage: "star.fill")
                }
            }
            Spacer()
            if !model.unreadableLessons.isEmpty {
                Button {
                    showUnreadable = true
                } label: {
                    Label("\(model.unreadableLessons.count) unreadable file(s)",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(palette.wrong)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showUnreadable) {
                    unreadablePopover
                }
            }
        }
    }
}

private extension HomeView {
    /// Names the files rather than just counting them. A count tells the
    /// learner something is wrong but not what, and these are plain JSON files
    /// they can open, keep, or discard.
    var unreadablePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("These files couldn't be read")
                .font(.headline)
                .foregroundStyle(palette.emphasizedText)
            Text("They're in \(model.dataDirectory.appending(path: "lessons").path). "
                 + "Usually this means a file was edited by hand or written by an "
                 + "older version. Nothing else is affected.")
                .font(.callout)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(model.unreadableLessons, id: \.self) { name in
                Text(name).font(.caption.monospaced())
            }

            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(
                        nil,
                        inFileViewerRootedAtPath:
                            model.dataDirectory.appending(path: "lessons").path)
                }
                Spacer()
                Button("Delete them", role: .destructive) {
                    model.deleteUnreadableLessons()
                    showUnreadable = false
                }
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}

struct LessonRow: View {
    let record: LessonRecord
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.lesson.spec.mode == .review
                  ? "arrow.triangle.2.circlepath" : "sparkles")
                .foregroundStyle(record.lesson.spec.mode == .review ? palette.review : palette.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.lesson.title)
                    .foregroundStyle(palette.emphasizedText)
                Text("\(record.lesson.exercises.count) exercises · ~\(record.lesson.estimatedMinutes) min · \(stateLabel)")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(palette.secondaryText)
        }
        .padding(14)
        .background(palette.surface, in: .rect(cornerRadius: 10))
    }

    private var stateLabel: String {
        switch record.state {
        case .generated: "not started"
        case .inProgress: "\(record.answers.count)/\(record.lesson.exercises.count) answered"
        case .completed: "done — needs your teacher"
        case .graded: "graded — not yet saved to Fluent"
        case .submitted: "graded"
        }
    }
}
