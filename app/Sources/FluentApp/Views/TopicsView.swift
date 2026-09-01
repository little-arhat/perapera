import SwiftUI
import FluentCore

/// What the learner is part-way through, least finished first.
///
/// Answers the question the app could not previously answer: every lesson
/// landed on the same material with no indication of whether that material was
/// nearly done. Fluent has tracked it all along in `spaced-repetition.json`;
/// nothing read it.
///
/// Tapping a topic writes it into the focus field rather than generating
/// immediately — the size and depth controls still apply, and spending money on
/// a click without confirmation would be the wrong kind of convenient.
struct TopicsView: View {
    let topics: [TopicProgress]
    let onPick: (TopicProgress) -> Void

    @Environment(\.palette) private var palette
    @State private var expanded = false

    private var visible: [TopicProgress] {
        expanded ? topics : Array(topics.prefix(5))
    }

    var body: some View {
        if topics.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Least finished first — tap one to aim the next lesson at it.")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    if topics.count > 5 {
                        Button(expanded ? "Show less" : "All \(topics.count)") {
                            expanded.toggle()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                    }
                }

                ForEach(visible) { topic in
                    Button { onPick(topic) } label: { row(topic) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ topic: TopicProgress) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(topic.name)
                    .foregroundStyle(palette.emphasizedText)
                if topic.due > 0 {
                    Text("\(topic.due) due")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(palette.review.opacity(0.18), in: .capsule)
                        .foregroundStyle(palette.review)
                }
                Spacer()
                Text("\(topic.verdict) · \(Int(topic.completion * 100))%")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            // Bands rather than one bar: "eight items, six of them new" is a
            // different situation from "eight items, six nearly mastered", and
            // a single percentage hides which one you are looking at.
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    band(topic.mastered, of: topic.total, geometry, palette.correct)
                    band(topic.strong, of: topic.total, geometry, palette.accent)
                    band(topic.learning, of: topic.total, geometry, palette.warning)
                    band(topic.new, of: topic.total, geometry, palette.secondaryText.opacity(0.3))
                }
            }
            .frame(height: 6)

            Text("\(topic.total) items · \(topic.mastered) mastered · \(topic.learning + topic.strong) learning · \(topic.new) new")
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(12)
        .background(palette.surface, in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func band(
        _ count: Int, of total: Int, _ geometry: GeometryProxy, _ color: Color
    ) -> some View {
        if count > 0, total > 0 {
            color.frame(width: geometry.size.width * CGFloat(count) / CGFloat(total))
        }
    }
}
