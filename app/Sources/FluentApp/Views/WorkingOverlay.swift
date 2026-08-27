import SwiftUI

/// Shown while the model is working.
///
/// A bare spinner for a 40-second wait reads as a hang. This shows what is
/// happening, how long it has taken, and the answer as it is being written —
/// so a long wait looks like progress rather than a stall, and a genuine stall
/// is visible as one.
struct WorkingOverlay: View {
    let status: String

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    /// Ticks once a second purely to redraw the elapsed counter.
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var elapsed: String {
        guard let started = model.progressStartedAt else { return "" }
        let seconds = Int(now.timeIntervalSince(started))
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
    }

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(status)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(palette.emphasizedText)
                        if let phase = model.progressPhase {
                            Text(phase)
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    Spacer()
                    Text(elapsed)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(palette.secondaryText)
                }

                if !model.progressText.isEmpty {
                    // The tail, not the head: what is arriving now is the
                    // interesting part, and it keeps the box a fixed size.
                    ScrollView {
                        Text(tail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 92)
                    .padding(8)
                    .background(palette.background, in: .rect(cornerRadius: 6))
                }
            }
            .padding(16)
            .frame(maxWidth: 560)
            .background(palette.surface, in: .rect(cornerRadius: 12))
            .shadow(radius: 12, y: 4)
            .padding(.bottom, 28)
        }
        .onReceive(clock) { now = $0 }
    }

    private var tail: String {
        let text = model.progressText
        return text.count <= 700 ? text : String(text.suffix(700))
    }
}
