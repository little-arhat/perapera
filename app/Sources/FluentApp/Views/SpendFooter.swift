import SwiftUI
import FluentCore

/// A quiet line saying what the last call cost, and what today has cost.
///
/// Always present rather than a popup that interrupts: the point is that
/// spending is *ambient* and checkable, not that it demands attention. Costs
/// here are fractions of a cent individually and add up over a month, which is
/// exactly the shape of a number people lose track of.
struct SpendFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var showingHistory = false

    var body: some View {
        HStack(spacing: 10) {
            if let latest = model.spending.latest {
                Text(latest.purpose)
                    .foregroundStyle(palette.secondaryText)
                Text(SpendLog.format(latest.costUSD))
                    .monospacedDigit()
                    .foregroundStyle(palette.emphasizedText)
                Text(shortModel(latest.model))
                    .foregroundStyle(palette.secondaryText)
            } else {
                Text("Nothing spent yet")
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()

            if model.spending.today > 0 {
                Text("today \(SpendLog.format(model.spending.today))")
                    .monospacedDigit()
                    .foregroundStyle(palette.secondaryText)
            }
            Button("Total \(SpendLog.format(model.spending.total))") {
                showingHistory = true
            }
            .buttonStyle(.plain)
            .monospacedDigit()
            .foregroundStyle(palette.secondaryText)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(palette.surface)
        .popover(isPresented: $showingHistory) { history }
    }

    /// `google/gemini-3.1-flash-image` is the vendor's name for it; the row has
    /// no space for that and the learner only needs which model.
    private func shortModel(_ id: String) -> String {
        id.split(separator: "/").last.map(String.init) ?? id
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent calls")
                .font(.headline)
                .foregroundStyle(palette.emphasizedText)
            if model.spending.entries.isEmpty {
                Text("Nothing yet.").foregroundStyle(palette.secondaryText)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.spending.entries.prefix(40)) { entry in
                            HStack {
                                Text(entry.purpose)
                                    .foregroundStyle(palette.emphasizedText)
                                Text(shortModel(entry.model))
                                    .foregroundStyle(palette.secondaryText)
                                Spacer()
                                Text(SpendLog.format(entry.costUSD))
                                    .monospacedDigit()
                                Text(entry.at, style: .relative)
                                    .foregroundStyle(palette.secondaryText)
                                    .frame(width: 74, alignment: .trailing)
                            }
                            .font(.caption)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}
