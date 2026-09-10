import SwiftUI
import PeraperaCore

/// Reading kana you have only ever seen in one typeface.
///
/// Free, offline and instant: the characters are known, the distractors are the
/// ones that actually confuse, and the typeface comes from what is installed. No
/// model call, so this can run every day without a budget conversation — which is
/// the point, because letterform recognition is a drilling problem, not a
/// generation problem.
struct ScriptDrillView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    @State private var question: ScriptDrill.Question?
    @State private var picked: String?
    @State private var streak = 0

    private var faces: [JapaneseFonts.Face] {
        JapaneseFonts.available(rendering: ScriptDrill.groups.flatMap(\.characters))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            header
            if let question {
                card(question)
            } else if faces.isEmpty {
                ContentUnavailableView(
                    "No Japanese typefaces found", systemImage: "character.magnify",
                    description: Text("This drill needs Japanese fonts installed. macOS "
                                      + "ships them; if they have been removed, the drill "
                                      + "has nothing to show you."))
            } else {
                ProgressView().onAppear(perform: nextQuestion)
            }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if question == nil { nextQuestion() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Script drill").font(.title2)
                    .foregroundStyle(palette.emphasizedText)
                Spacer()
                if streak > 1 {
                    Text("\(streak) in a row")
                        .font(.caption)
                        .foregroundStyle(palette.correct)
                }
            }
            Text("The same kana in a brush face, a rounded shop sign or a textbook hand "
                 + "are different reading problems. This one costs nothing and works "
                 + "offline.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
        }
    }

    private func card(_ question: ScriptDrill.Question) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Which character is this?")
                .font(.headline)
                .foregroundStyle(palette.emphasizedText)

            HStack {
                Spacer()
                Text(question.answer)
                    .font(.custom(question.family, size: 160))
                    .foregroundStyle(palette.emphasizedText)
                    .frame(height: 190)
                Spacer()
            }

            // Named after the answer is given, not before: knowing it is a brush
            // face is a hint, and the whole exercise is reading without one.
            Text(picked == nil
                 ? "Set in one of \(faces.count) installed typefaces"
                 : "\(question.family) — \(JapaneseFonts.context(for: question.family))")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 10) {
                ForEach(question.options, id: \.self) { option in
                    Button { answer(option, to: question) } label: {
                        Text(option)
                            .font(.system(size: 34))
                            .frame(minWidth: 64, minHeight: 56)
                            .background(background(for: option, in: question),
                                        in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(picked != nil)
                }
            }

            if picked != nil {
                VStack(alignment: .leading, spacing: 8) {
                    // fixedSize, or the explanation is squeezed to a single line
                    // and truncated with an ellipsis -- and the explanation is the
                    // entire lesson of a wrong answer.
                    Text(question.group.difference)
                        .font(.callout)
                        .foregroundStyle(palette.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                    // Side by side in the same face, which is where the
                    // difference is actually visible.
                    HStack(spacing: 20) {
                        ForEach(question.group.characters, id: \.self) { character in
                            VStack(spacing: 2) {
                                Text(character)
                                    .font(.custom(question.family, size: 64))
                                    .foregroundStyle(character == question.answer
                                                     ? palette.correct : palette.bodyText)
                                Text(character)
                                    .font(.system(size: 15))
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                    Button("Next") { nextQuestion() }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(14)
                .background(palette.surface, in: .rect(cornerRadius: 10))
            }
        }
        .padding(20)
        .background(palette.surface.opacity(0.6), in: .rect(cornerRadius: 12))
    }

    private func background(for option: String, in question: ScriptDrill.Question) -> Color {
        guard let picked else { return palette.surface }
        if option == question.answer { return palette.correct.opacity(0.3) }
        if option == picked { return palette.wrong.opacity(0.3) }
        return palette.surface
    }

    private func answer(_ option: String, to question: ScriptDrill.Question) {
        picked = option
        let right = option == question.answer
        streak = right ? streak + 1 : 0
        model.recordScript(question.answer, wasCorrect: right)
    }

    private func nextQuestion() {
        picked = nil
        question = ScriptDrill.next(
            seen: model.scriptProgress.seen,
            correct: model.scriptProgress.correct,
            families: faces.map(\.family))
    }
}
