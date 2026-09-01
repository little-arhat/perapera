import SwiftUI
import FluentCore

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.textScale) private var scale

    @State private var size: LessonSpec.Size = .medium
    @State private var depth: LessonSpec.Depth = .standard
    @State private var photos = 0
    @State private var focus = ""
    @State private var name = ""
    @State private var note = ""
    @State private var showUnreadable = false
    @State private var labelling: LessonRecord?

    /// What the current settings would ask for. Needs the profile, so it is
    /// nil until the databases have loaded.
    private var plan: LessonPlan? {
        guard let snapshot = model.snapshot else { return nil }
        return LessonPlan.plan(
            size: size, depth: depth,
            level: snapshot.databases.learner_profile.learner.current_level,
            totalSessions: snapshot.databases.learner_profile.total_sessions,
            mode: .lesson,
            dueCount: snapshot.computed.due_reviews_count)
    }

    /// Collapsed summaries. Each names the state you would otherwise have to
    /// open the panel to see.
    private var generatorSummary: String {
        let photoNote = photos > 0 ? " · \(photos) photo\(photos == 1 ? "" : "s")" : ""
        return "\(size.label.lowercased()) · \(depth.label.lowercased())"
            + photoNote
            + (focus.isEmpty ? "" : " · \(focus)")
    }

    private var topicsSummary: String {
        let all = model.topics
        guard let weakest = all.first else { return "nothing tracked yet" }
        let due = all.reduce(0) { $0 + $1.due }
        let dueNote = due > 0 ? " · \(due) due" : ""
        return "\(all.count) topics · weakest \(weakest.name) \(Int(weakest.completion * 100))%"
            + dueNote
    }

    private var pending: [LessonRecord] {
        model.records.filter { $0.state != .submitted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                CollapsibleSection(
                    title: "New lesson",
                    summary: generatorSummary,
                    storageKey: "generator"
                ) { generator }
                CollapsibleSection(
                    title: "Where you are",
                    summary: topicsSummary,
                    storageKey: "topics"
                ) {
                    TopicsView(topics: model.topics) { topic in
                        focus = topic.name
                    }
                }
                if !pending.isEmpty { pendingSection }
                footer
            }
            .padding(32)
            .frame(maxWidth: scale.width(760), alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $labelling) { LabelSheet(record: $0) }
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
                            Text($0.label).tag($0).help($0.help)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("How many distinct topics the lesson covers.\n"
                          + LessonSpec.Size.allCases
                              .map { "\($0.label) — \($0.help)" }
                              .joined(separator: "\n"))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repetition").font(.caption)
                        .foregroundStyle(palette.secondaryText)
                    Picker("Depth", selection: $depth) {
                        ForEach(LessonSpec.Depth.allCases, id: \.self) {
                            Text($0.detailedLabel).tag($0).help($0.help)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("How many times each topic is practised.\n"
                          + LessonSpec.Depth.allCases
                              .map { "\($0.label) — \($0.help)" }
                              .joined(separator: "\n"))
                }
            }

            // The concrete number, before anything is spent. Words alone left
            // no way to tell a small lesson from a misread request.
            Text(plan?.summary ?? "\(size.label), \(depth.itemsPerSet) items per set")
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)

            // The only control in the app where the number is money, so it
            // starts at zero and states the cost rather than burying it.
            if model.canGenerateImages {
                HStack(spacing: 10) {
                    Stepper(
                        "Photographs: \(photos)",
                        value: $photos, in: 0...4)
                        .fixedSize()
                        .help("Read Japanese off a generated photo of a sign, "
                              + "menu or noren — the skill a screen cannot train.")
                    Text(photos == 0
                         ? "none — free"
                         : String(format: "about $%.2f, generated and checked",
                                  Double(photos) * 0.07))
                        .font(.caption2)
                        .foregroundStyle(photos == 0
                                         ? palette.secondaryText : palette.warning)
                }
            }

            TextField("Focus (optional) — e.g. counters, train station, kanji reading",
                      text: $focus)
                .textFieldStyle(.roundedBorder)

            // Focus steers the generator; name and note are the learner's own,
            // and never reach the model. Queuing several lessons ahead of time
            // is only useful if you can tell them apart afterwards.
            HStack(spacing: 10) {
                TextField("Name (optional) — how you'll recognise it later",
                          text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("Note (optional) — when or why to do it", text: $note)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await generate(.lesson) }
                } label: {
                    Label("Generate Lesson", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)

                Button {
                    Task { await generate(.review) }
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

    /// Generates, then clears the labels so the next lesson starts fresh —
    /// carrying a stale name into the following lesson is worse than no name.
    private func generate(_ mode: LessonSpec.Mode) async {
        await model.generate(mode: mode, size: size, depth: depth,
                             focus: focus, name: name, note: note,
                             photoExercises: photos)
        name = ""
        note = ""
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
                .contextMenu {
                    Button("Rename…") { labelling = record }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
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
            // A word, not just a pictogram. "Lesson" and "Review" are the two
            // things a row can be, and an icon alone left that a guess — the
            // symbols for "new material" and "spaced repetition" are not
            // conventions anyone knows.
            VStack(spacing: 3) {
                Image(systemName: kind.icon)
                    .foregroundStyle(kind.tint(palette))
                Text(kind.label)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
            .frame(width: 52)
            .help(kind.explanation)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayTitle)
                    .foregroundStyle(palette.emphasizedText)
                if let note = record.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()

            if record.photoCount > 0 {
                Label("\(record.photoCount)", systemImage: "photo")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                    .help("^[\(record.photoCount) photograph](inflect: true) to read")
            }

            Image(systemName: "chevron.right").foregroundStyle(palette.secondaryText)
        }
        .padding(14)
        .background(palette.surface, in: .rect(cornerRadius: 10))
    }

    /// What kind of lesson this is, said in words.
    private enum Kind {
        case lesson, review

        var label: String {
            switch self {
            case .lesson: "Lesson"
            case .review: "Review"
            }
        }

        var icon: String {
            switch self {
            case .lesson: "sparkles"
            case .review: "arrow.triangle.2.circlepath"
            }
        }

        var explanation: String {
            switch self {
            case .lesson: "New material, chosen around your focus and weak spots."
            case .review: "Items spaced repetition says are due now."
            }
        }

        func tint(_ palette: Palette) -> Color {
            switch self {
            case .lesson: palette.accent
            case .review: palette.review
            }
        }
    }

    private var kind: Kind {
        record.lesson.spec.mode == .review ? .review : .lesson
    }

    private var subtitle: String {
        let spec = record.lesson.spec
        return [
            "\(record.lesson.itemCount) questions",
            "\(spec.size.label.lowercased()) · \(spec.depth.label.lowercased())",
            LessonRow.relativeDate(record.lesson.generatedAt),
            stateLabel,
        ].joined(separator: " · ")
    }

    /// "2 hours ago", not a timestamp nobody parses at a glance.
    static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var stateLabel: String {
        switch record.state {
        case .generated: "not started"
        case .inProgress: "\(record.answers.count)/\(record.lesson.exercises.count) answered"
        case .completed: "done — needs your teacher"
        case .graded: "graded — not yet saved to Fluent"
        case .submitted:
            // The score, not just the word. A graded lesson in a list is only
            // useful if it says how it went.
            if let score = record.finalScore {
                "\(score.correct)/\(score.total) · \(Int(Double(score.correct) / Double(score.total) * 100))%"
            } else {
                "graded"
            }
        }
    }
}
