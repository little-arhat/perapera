import SwiftUI

/// A section that folds to a single bar showing its gist.
///
/// The home screen accumulates panels that are each useful occasionally and in
/// the way constantly. Collapsing has to leave something behind, though — a bar
/// saying only "Where you are" is a worse control than no control, because you
/// have to open it to learn whether opening it was worth it. So the collapsed
/// state carries a summary.
///
/// The open/closed choice is remembered: it is a working preference, and having
/// to re-collapse the same panel every launch is its own annoyance.
struct CollapsibleSection<Content: View>: View {
    let title: String
    /// Shown beside the title when collapsed. Keep it to a few words.
    let summary: String
    let storageKey: String
    @ViewBuilder let content: () -> Content

    @Environment(\.palette) private var palette
    @AppStorage private var isExpanded: Bool

    init(
        title: String,
        summary: String,
        storageKey: String,
        expandedByDefault: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.storageKey = storageKey
        self.content = content
        _isExpanded = AppStorage(wrappedValue: expandedByDefault, "expanded.\(storageKey)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(palette.secondaryText)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(palette.emphasizedText)
                    if !isExpanded, !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded { content() }
        }
    }
}
