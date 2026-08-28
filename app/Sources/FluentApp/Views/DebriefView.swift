import SwiftUI
import FluentCore

/// Shown when a lesson is finished. Before submission it reports only what the
/// app actually knows -- the auto-graded score -- and says plainly that the rest
/// is unjudged. After submission it shows the teacher's feedback.
struct DebriefView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.textScale) private var scale

    let record: LessonRecord

    private var live: LessonRecord { model.record(id: record.id) ?? record }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let feedback = live.feedback {
                    graded(feedback)
                } else {
                    unsubmitted
                }
                Button("Home") { model.screen = .home }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(32)
            .frame(maxWidth: scale.width(760), alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        let score = live.autoGradedScore
        return VStack(alignment: .leading, spacing: 8) {
            Text(live.lesson.title)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(palette.emphasizedText)
            HStack(spacing: 16) {
                Label("\(score.correct)/\(score.total) auto-graded",
                      systemImage: "checkmark.circle")
                Label("\(live.durationMinutes) min", systemImage: "clock")
                if !live.exercisesNeedingTeacher.isEmpty {
                    Label("\(live.exercisesNeedingTeacher.count) need judgement",
                          systemImage: "person.fill.questionmark")
                        .foregroundStyle(palette.review)
                }
            }
            .font(.callout)
            .foregroundStyle(palette.secondaryText)
        }
    }

    private var unsubmitted: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Not graded yet")
                .font(.headline)
                .foregroundStyle(palette.emphasizedText)
            Text("The score above counts only the exercises the app can grade on its own. Sending this to your teacher grades the rest, records what you got wrong, and updates your review schedule.")
                .foregroundStyle(palette.bodyText)

            Button {
                Task { await model.submit(id: live.id) }
            } label: {
                Label("Finish lesson", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(palette.accent)
            .disabled(model.isSubmitting)

            Text("Needs a connection. Until then this lesson waits here — nothing is lost.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(20)
        .background(palette.surface, in: .rect(cornerRadius: 12))
    }

    private func graded(_ feedback: Feedback) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let overall = feedback.overallComment {
                Text(.init(overall))
                    .selectableIf(scale.selectable)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.surface, in: .rect(cornerRadius: 12))
            }

            if !feedback.graded.isEmpty {
                section("Your written answers") {
                    ForEach(feedback.graded, id: \.exerciseId) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(promptFor(item.exerciseId))
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(palette.emphasizedText)
                                Spacer()
                                Text("\(item.score)/10")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(item.score >= 6 ? palette.correct : palette.wrong)
                            }
                            Text(.init(item.comment)).font(.callout)
                                .selectableIf(scale.selectable)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.surface, in: .rect(cornerRadius: 10))
                    }
                }
            }

            if let errors = feedback.errors, !errors.isEmpty {
                section("Tracked for review") {
                    ForEach(errors, id: \.patternId) { error in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(palette.severity(error.severity))
                                .frame(width: 8, height: 8).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(error.yourAnswer) → \(error.correctAnswer)")
                                    .foregroundStyle(palette.emphasizedText)
                                    .selectableIf(scale.selectable)
                                Text(error.notes ?? error.category)
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if let breakthroughs = feedback.breakthroughs, !breakthroughs.isEmpty {
                section("Breakthroughs") {
                    ForEach(breakthroughs, id: \.self) { item in
                        Label(item, systemImage: "sparkles")
                            .foregroundStyle(palette.correct)
                    }
                }
            }

            if let focus = feedback.focusNextSession, !focus.isEmpty {
                section("Next time") {
                    ForEach(Array(focus.enumerated()), id: \.offset) { i, item in
                        Label("\(i + 1). \(item)", systemImage: "target")
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(palette.emphasizedText)
            content()
        }
    }

    private func promptFor(_ exerciseId: String) -> String {
        live.lesson.exercises.first { $0.id == exerciseId }?.prompt ?? exerciseId
    }
}
