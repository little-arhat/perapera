import Charts
import SwiftUI
import FluentCore

/// How the learner is actually doing.
///
/// Everything here is read from Fluent's databases and computed by
/// `update-db.py`; nothing is recomputed in Swift. `/fluent-progress` in the
/// terminal did this better than the app for months, which was the wrong way
/// round for the surface the learner spends their time in.
///
/// Most of this is not a chart. A streak, a session count and an overall
/// accuracy are single headline numbers, and drawing them as bars would add
/// decoration without adding information. The one thing that genuinely changes
/// over time — accuracy per session — gets the one plot.
struct ProgressDashboard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    private var snapshot: FluentStore.Snapshot? { model.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let snapshot {
                    headline(snapshot)
                    trend(snapshot)
                    skills(snapshot)
                    topics
                } else {
                    ContentUnavailableView("No progress yet",
                                           systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Finish a lesson and it "
                                               + "will show up here."))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Headline numbers

    private func headline(_ snapshot: FluentStore.Snapshot) -> some View {
        let profile = snapshot.databases.learner_profile
        let stats = snapshot.databases.progress_db.overall_stats
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(profile.learner.name) · \(profile.learner.target_language) "
                 + "\(profile.learner.current_level) → \(profile.learner.target_level)")
                .font(.title3)
                .foregroundStyle(palette.emphasizedText)

            HStack(spacing: 12) {
                tile("Streak", "\(profile.current_streak_days)",
                     unit: profile.current_streak_days == 1 ? "day" : "days",
                     warn: !snapshot.computed.streak_active)
                tile("Sessions", "\(profile.total_sessions)", unit: "done")
                tile("Studied", "\(stats?.total_study_minutes ?? 0)", unit: "minutes")
                tile("Accuracy",
                     stats?.accuracy_rate.map { "\(Int($0 * 100))" } ?? "—",
                     unit: "% overall")
                tile("Due", "\(snapshot.computed.due_reviews_count)", unit: "to review")
            }
        }
    }

    /// A single number and what it counts. The label carries the meaning, so the
    /// tile never depends on colour to be read.
    private func tile(_ name: String, _ value: String, unit: String,
                      warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(warn ? palette.warning : palette.emphasizedText)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(minWidth: 84, alignment: .leading)
        .padding(12)
        .background(palette.surface, in: .rect(cornerRadius: 10))
    }

    // MARK: - Accuracy over time

    @ViewBuilder
    private func trend(_ snapshot: FluentStore.Snapshot) -> some View {
        let points = snapshot.databases.progress_db.accuracy_trend ?? []
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Accuracy per session")
                    .font(.headline)
                    .foregroundStyle(palette.emphasizedText)

                // One series, so no legend: the title names it. The band is the
                // 60-70% the methodology aims for, drawn behind the line so a
                // session can be read as on-target rather than merely high.
                Chart {
                    RectangleMark(yStart: .value("Floor", 0.6),
                                  yEnd: .value("Ceiling", 0.7))
                        .foregroundStyle(palette.correct.opacity(0.12))

                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Date", point.date),
                                 y: .value("Accuracy", point.accuracy))
                            .foregroundStyle(palette.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Date", point.date),
                                  y: .value("Accuracy", point.accuracy))
                            .foregroundStyle(palette.accent)
                            .symbolSize(60)
                    }
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1]) { value in
                        AxisGridLine().foregroundStyle(palette.secondaryText.opacity(0.25))
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text("\(Int(d * 100))%")
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let date = value.as(String.self) {
                                Text(date.suffix(5))
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                }
                .frame(height: 160)

                Text("The shaded band is the 60-70% the methodology aims for. Higher is "
                     + "not better: consistently above it means the material is too easy "
                     + "to be teaching much.")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Per skill

    private func skills(_ snapshot: FluentStore.Snapshot) -> some View {
        let mastery = snapshot.databases.mastery_db.skills ?? [:]
        let progress = snapshot.databases.progress_db.skill_progress ?? [:]
        let names = Set(mastery.keys).union(progress.keys).sorted()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Skills")
                .font(.headline)
                .foregroundStyle(palette.emphasizedText)

            // A table rather than a second chart. Mastery, accuracy and how long
            // ago are three different measures, and putting them on one pair of
            // axes would misrepresent all three.
            ForEach(names, id: \.self) { name in
                HStack(spacing: 12) {
                    Text(name.capitalized)
                        .frame(width: 96, alignment: .leading)
                        .foregroundStyle(palette.bodyText)
                    // Mastery is drawn as filled marks out of five, so it reads
                    // without relying on colour.
                    masteryMarks(mastery[name]?.mastery_level ?? 0)
                    Text(progress[name]?.accuracy.map { "\(Int($0 * 100))%" } ?? "—")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(palette.bodyText)
                    Text("\(progress[name]?.exercises_completed ?? 0) done")
                        .font(.caption)
                        .frame(width: 70, alignment: .trailing)
                        .foregroundStyle(palette.secondaryText)
                    Text(progress[name]?.last_practiced ?? "never")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: .rect(cornerRadius: 12))
    }

    private func masteryMarks(_ level: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { step in
                Image(systemName: step < level ? "circle.fill" : "circle")
                    .font(.system(size: 8))
                    .foregroundStyle(step < level ? palette.accent : palette.secondaryText)
            }
        }
        .frame(width: 60, alignment: .leading)
        .help("Mastery \(level) of 5")
    }

    // MARK: - Topics

    @ViewBuilder
    private var topics: some View {
        if !model.topics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Topics, least finished first")
                    .font(.headline)
                    .foregroundStyle(palette.emphasizedText)
                // Picking a topic from here jumps to Practice with it as the
                // focus, so the dashboard is somewhere to act rather than only
                // somewhere to look.
                TopicsView(topics: model.topics) { topic in
                    model.show(.practice)
                    model.pendingFocus = topic.name
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: .rect(cornerRadius: 12))
        }
    }
}
