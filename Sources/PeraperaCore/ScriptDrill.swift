import Foundation

/// Telling kana apart when the letterform is unfamiliar.
///
/// Kana on screen and kana in the street are different perceptual tasks. A
/// learner who reads すし instantly in Hiragino stalls on the same word brushed
/// on a noren or set in a rounded 1970s display face. Showing one typeface
/// trains the easy half of the skill and silently omits the hard half.
///
/// The drill is generated locally: the characters are known, the distractors are
/// the ones that actually confuse, and the typeface comes from what is installed.
/// Nothing here costs anything or needs a network, which is why it can run every
/// day without a budget conversation.
public enum ScriptDrill {
    /// Characters that differ by one feature, and what that feature is.
    ///
    /// Not "similar-looking kana" in general: each group is a specific,
    /// documented failure, and the explanation is what the learner takes away
    /// when they get it wrong.
    public struct Group: Equatable, Sendable, Identifiable {
        public let id: String
        public let characters: [String]
        /// What actually separates them, in one line.
        public let difference: String
        /// Whether looking at the glyph can settle it.
        ///
        /// ー and 一 are drawn as the same horizontal stroke in most faces, and
        /// カ and 力 differ by a hair. They are real confusions and worth
        /// knowing about, but "which character is this?" is the wrong question
        /// to ask about them: the answer is a coin flip, and being told you are
        /// wrong about a stroke you read correctly teaches nothing. Context
        /// settles those, so they are shown as a reference rather than drilled.
        public let distinguishedByShape: Bool

        public init(id: String, characters: [String], difference: String,
                    distinguishedByShape: Bool = true) {
            self.id = id
            self.characters = characters
            self.difference = difference
            self.distinguishedByShape = distinguishedByShape
        }
    }

    public static let groups: [Group] = [
        Group(id: "shi-tsu", characters: ["シ", "ツ"],
              difference: "Stroke direction: シ's strokes come in from the left and sweep "
                  + "up; ツ's come down from the top. Brush faces exaggerate it, casual "
                  + "handwriting almost erases it."),
        Group(id: "so-n", characters: ["ソ", "ン"],
              difference: "Same angle rule as シ/ツ: ン sweeps up from the lower left, "
                  + "ソ comes down from the upper right."),
        Group(id: "ne-re-wa", characters: ["ね", "れ", "わ"],
              difference: "Identical left side; the whole difference is the right-hand "
                  + "stroke — ね loops closed, れ hooks out, わ curves round without closing."),
        Group(id: "nu-me", characters: ["ぬ", "め"],
              difference: "ぬ finishes with a loop, め does not. In a brush face the loop "
                  + "can close up until it is nearly a blob."),
        Group(id: "ru-ro", characters: ["る", "ろ"],
              difference: "る ends in a loop, ろ ends open. The one feature, again."),
        Group(id: "ko-yu", characters: ["コ", "ユ"],
              difference: "Orientation: コ opens to the right, ユ opens to the left and "
                  + "sits on a base stroke."),
        Group(id: "chouon-ichi", characters: ["ー", "一"],
              difference: "ー is the long-vowel mark and belongs to katakana; 一 is the "
                  + "kanji for one. Most faces draw them as the same stroke, so only "
                  + "context tells you which you are looking at — ー follows kana in a "
                  + "borrowed word, 一 stands alone or in a compound.",
              distinguishedByShape: false),
        Group(id: "ha-ho", characters: ["は", "ほ"],
              difference: "ほ has one more horizontal stroke than は."),
        Group(id: "ki-sa", characters: ["き", "さ"],
              difference: "き has two crossing strokes, さ one. Rounded faces join them "
                  + "both into a single curve."),
        Group(id: "ku-ta", characters: ["ク", "タ"],
              difference: "タ has an extra stroke through the middle."),
        Group(id: "wa-ra-fu", characters: ["ワ", "ラ", "フ"],
              difference: "ワ closes at the top-right, ラ has a separate stroke above, "
                  + "フ is a single stroke."),
        Group(id: "ka-chikara", characters: ["カ", "力"],
              difference: "Katakana カ and the kanji 力 (power). Near-identical in every "
                  + "face; context decides. Knowing they are two different characters is "
                  + "the whole lesson.",
              distinguishedByShape: false),
    ]

    /// One question: what character is this, in this typeface?
    public struct Question: Equatable, Sendable {
        public let group: Group
        public let answer: String
        /// The answer plus its confusables, in the order to show them.
        public let options: [String]
        /// The font family to draw the target in.
        public let family: String

        public init(group: Group, answer: String, options: [String], family: String) {
            self.group = group
            self.answer = answer
            self.options = options
            self.family = family
        }

        public var correctIndex: Int { options.firstIndex(of: answer) ?? 0 }
    }

    /// Builds a question, preferring whatever the learner is worst at.
    ///
    /// `seen` and `correct` are per character, so a learner who has シ but not ツ
    /// is asked about ツ. Ties break on least-seen, so a fresh group comes up
    /// before one already answered ten times.
    /// The groups this drill can actually ask about.
    public static var drillable: [Group] { groups.filter(\.distinguishedByShape) }

    /// The ones a drill cannot settle, kept as a reference.
    public static var lookalikes: [Group] { groups.filter { !$0.distinguishedByShape } }

    public static func next(
        seen: [String: Int], correct: [String: Int], families: [String],
        randomness: (Int) -> Int = { Int.random(in: 0..<max(1, $0)) }
    ) -> Question? {
        guard !families.isEmpty else { return nil }

        let ranked = drillable
            .map { group -> (Group, Double, Int) in
                let attempts = group.characters.reduce(0) { $0 + (seen[$1] ?? 0) }
                let right = group.characters.reduce(0) { $0 + (correct[$1] ?? 0) }
                // An unseen group scores as if it were half wrong, so new
                // material competes with known-weak material instead of waiting
                // behind it forever.
                let accuracy = attempts == 0 ? 0.5 : Double(right) / Double(attempts)
                return (group, accuracy, attempts)
            }
            .sorted { ($0.1, Double($0.2)) < ($1.1, Double($1.2)) }

        guard let group = ranked.first?.0 else { return nil }
        let weakest = group.characters
            .min { lhs, rhs in
                let l = (Double(correct[lhs] ?? 0) + 0.5) / Double((seen[lhs] ?? 0) + 1)
                let r = (Double(correct[rhs] ?? 0) + 0.5) / Double((seen[rhs] ?? 0) + 1)
                return l < r
            } ?? group.characters[0]

        return Question(group: group, answer: weakest,
                        options: group.characters,
                        family: families[randomness(families.count)])
    }
}
