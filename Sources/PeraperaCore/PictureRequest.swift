import Foundation

/// A photograph made on demand rather than as part of a lesson.
///
/// Composed locally: the surface descriptions below are templates, so asking
/// for one costs a single image call and nothing for a model to write the
/// scene. The learner supplies what the sign should *say*; the app supplies
/// what it should look like.
public struct PictureRequest: Equatable, Sendable {
    /// Where the writing appears. These are the surfaces that are genuinely
    /// harder to read than a screen — the reason the exercise exists.
    public enum Surface: String, CaseIterable, Sendable, Identifiable {
        case enamelPlate, noren, menuBoard, stationSign, shopWindow, handwrittenNote

        /// One at random.
        ///
        /// Text in the wild does not announce what it is written on, and always
        /// choosing the familiar surface trains the surface as much as the word.
        public static func surprise(
            using pick: ([Surface]) -> Surface = { $0.randomElement() ?? .stationSign }
        ) -> Surface {
            pick(allCases)
        }

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .enamelPlate: "Enamel plate"
            case .noren: "Noren curtain"
            case .menuBoard: "Menu board"
            case .stationSign: "Station sign"
            case .shopWindow: "Shop window"
            case .handwrittenNote: "Handwritten note"
            }
        }

        public var summary: String {
            switch self {
            case .enamelPlate: "Weathered, high contrast. The gentlest of these."
            case .noren: "Brush-painted on hanging cloth, folded and angled."
            case .menuBoard: "Marker on wood, everyday handwriting."
            case .stationSign: "Clean gothic type. Closest to a screen."
            case .shopWindow: "Bold display katakana, reflections, at an angle."
            case .handwrittenNote: "Casual pen. The hardest to read."
            }
        }

        /// How much harder than a screen, roughly. Used to order the list so a
        /// beginner is not first offered handwriting.
        public var difficulty: Int {
            switch self {
            case .stationSign: 1
            case .enamelPlate: 2
            case .shopWindow: 3
            case .menuBoard: 4
            case .noren: 4
            case .handwrittenNote: 5
            }
        }

        /// The scene handed to the image model. The literal text is added by
        /// the pipeline, which also verifies it came out right.
        public func scene(language: String) -> String {
            switch self {
            case .enamelPlate:
                return "A close-up photograph of an old weathered enamel metal "
                    + "sign bolted to a concrete wall, black text on white, "
                    + "rust creeping in at the edges, daylight, slight angle."
            case .noren:
                return "A photograph of a navy noren curtain hanging in a shop "
                    + "doorway, the text brush-painted in white, the cloth "
                    + "folded and moving slightly, warm afternoon light."
            case .menuBoard:
                return "A close-up photograph of a handwritten menu board on "
                    + "wood inside a small restaurant, black marker in natural "
                    + "everyday handwriting, warm interior lighting."
            case .stationSign:
                return "A photograph of a \(language) railway station sign, "
                    + "white board with black gothic lettering on a pole, "
                    + "platform blurred behind, daylight."
            case .shopWindow:
                return "A photograph of a shop window poster in bold display "
                    + "lettering, seen at an angle with a slight reflection in "
                    + "the glass, street visible behind, daylight."
            case .handwrittenNote:
                return "A close-up photograph of a handwritten note on paper "
                    + "taped to a glass door, casual ballpoint handwriting, "
                    + "slightly creased paper, daylight."
            }
        }
    }

    /// Which writing systems the picture may use.
    ///
    /// A real sign picks one, so this is a filter on what may be *asked for*
    /// rather than a set to display at once. Turning kanji off is how a learner
    /// says "I want to practise kana"; leaving only katakana on is how they
    /// drill the script most likely to be a loanword they could otherwise guess.
    public struct Scripts: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let kanji = Scripts(rawValue: 1 << 0)
        public static let hiragana = Scripts(rawValue: 1 << 1)
        public static let katakana = Scripts(rawValue: 1 << 2)
        public static let all: Scripts = [.kanji, .hiragana, .katakana]

        public var isEmpty: Bool { rawValue == 0 }
    }

    /// What the picture should say, and what counts as reading it.
    public let targets: [String]
    public let accepted: [String]
    public let surface: Surface
    /// Where the words came from, for the library's provenance line.
    public let sourceLabel: String

    public init(
        targets: [String], accepted: [String], surface: Surface, sourceLabel: String
    ) {
        self.targets = targets
        self.accepted = accepted
        self.surface = surface
        self.sourceLabel = sourceLabel
    }

    /// Ordered so the easier surfaces come first.
    public static var surfaces: [Surface] {
        Surface.allCases.sorted {
            $0.difficulty == $1.difficulty
                ? $0.label < $1.label : $0.difficulty < $1.difficulty
        }
    }

    /// The forms of a word that the chosen scripts allow.
    ///
    /// A kanji form is only available when the word actually has one, and a
    /// kana form only when the reading is known — a katakana rendering cannot
    /// be invented from 切符 alone.
    public static func forms(
        written: String, reading: String?, scripts: Scripts
    ) -> [String] {
        var out: [String] = []
        if scripts.contains(.kanji), KanaInput.containsKanji(written) {
            out.append(written)
        }
        // Without kanji, the written form may itself already be kana.
        let kana = (reading?.isEmpty == false ? reading! : nil)
            ?? (KanaInput.containsKanji(written) ? nil : written)
        if let kana {
            if scripts.contains(.hiragana) {
                out.append(KanaInput.convertKana(kana, to: .hiragana))
            }
            if scripts.contains(.katakana) {
                out.append(KanaInput.convertKana(kana, to: .katakana))
            }
        }
        // Deduplicate: a word already in hiragana yields the same string twice
        // when both kana scripts are on.
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// Everything that counts as having read the sign.
    ///
    /// Always both kana scripts plus the written form, regardless of what the
    /// picture shows: the learner is reading the word, and answering キップ for
    /// a hiragana sign is not a mistake.
    public static func acceptedForms(written: String, reading: String?) -> [String] {
        var out = [written]
        if let reading, !reading.isEmpty {
            out.append(KanaInput.convertKana(reading, to: .hiragana))
            out.append(KanaInput.convertKana(reading, to: .katakana))
        } else if !KanaInput.containsKanji(written) {
            out.append(KanaInput.convertKana(written, to: .hiragana))
            out.append(KanaInput.convertKana(written, to: .katakana))
        }
        var seen = Set<String>()
        return out.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Builds a request from a saved word.
    ///
    /// One of the allowed forms goes on the sign; every form is accepted as an
    /// answer. That is the exercise: recognise the word however it is written,
    /// then say it.
    public static func from(
        _ item: SavedItem, surface: Surface, scripts: Scripts = .all
    ) -> PictureRequest? {
        let written = Furigana.stripped(item.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty else { return nil }

        let available = forms(written: written, reading: item.reading, scripts: scripts)
        guard let shown = available.randomElement() else { return nil }

        // A gloss is not a reading, so it is never accepted as one.
        return PictureRequest(
            targets: [shown],
            accepted: acceptedForms(written: written, reading: item.reading),
            surface: surface,
            sourceLabel: item.gloss.isEmpty ? written : "\(written) — \(item.gloss)")
    }

    /// Builds one from free text the learner typed.
    public static func from(
        text: String, surface: Surface, scripts: Scripts = .all
    ) -> PictureRequest? {
        let written = Furigana.stripped(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty, written.count <= 12 else { return nil }

        let available = forms(written: written, reading: nil, scripts: scripts)
        // Typed kanji with kanji switched off leaves nothing to show: the
        // reading cannot be derived from the characters alone.
        guard let shown = available.randomElement() else { return nil }
        return PictureRequest(
            targets: [shown],
            accepted: acceptedForms(written: written, reading: nil),
            surface: surface, sourceLabel: written)
    }
}

/// A picture made outside any lesson.
///
/// Kept apart from lesson images because it has no lesson: inventing a fake
/// `LessonRecord` to hold one would put a lie in the archive, which is the one
/// place that has to stay literally true.
public struct StandalonePicture: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let fileName: String
    public let targets: [String]
    public let accepted: [String]
    public let question: String?
    public let sourceLabel: String
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        fileName: String, targets: [String], accepted: [String],
        question: String?, sourceLabel: String, createdAt: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.targets = targets
        self.accepted = accepted
        self.question = question
        self.sourceLabel = sourceLabel
        self.createdAt = createdAt
    }
}
