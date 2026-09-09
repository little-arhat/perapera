import SwiftUI
import PeraperaCore

/// The photograph a recognition exercise is built around.
///
/// Deliberately large and uncropped: the difficulty *is* the angle, the wear
/// and the letterforms, so shrinking it to a thumbnail would remove the thing
/// being practised.
///
/// The transcript is never shown before answering, for the same reason the
/// listening transcript is hidden — reading the answer defeats the exercise.
struct RecognitionView: View {
    let image: Exercise.ImageSpec
    let fileURL: URL?
    let revealed: Bool

    @Environment(\.palette) private var palette
    @Environment(\.textScale) private var scale
    @State private var zoomed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fileURL, let loaded = NSImage(contentsOf: fileURL) {
                Image(nsImage: loaded)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: zoomed ? 640 : 340)
                    .clipShape(.rect(cornerRadius: 10))
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { zoomed.toggle() } }
                    .help("Click to enlarge — the point is reading it as you would in the street")
            } else {
                // Should not happen: an exercise whose image failed to build is
                // dropped at generation. Saying so beats an empty box.
                Label("This picture is missing", systemImage: "photo")
                    .foregroundStyle(palette.wrong)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(palette.surface, in: .rect(cornerRadius: 10))
            }

            if let question = image.question, !question.isEmpty {
                Text(question)
                    .font(.system(size: scale.size(17)))
                    .foregroundStyle(palette.secondaryText)
                    .selectableIf(scale.selectable)
            }

            if revealed {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What the sign says")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                    ForEach(image.targets, id: \.self) { target in
                        RubyText(annotated: target, showFurigana: true, size: 19)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface, in: .rect(cornerRadius: 8))
            }
        }
    }
}
