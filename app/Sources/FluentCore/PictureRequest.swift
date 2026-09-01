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

    /// Builds a request from a saved word.
    ///
    /// The written form goes on the sign and the reading is what the learner
    /// types — which is the whole exercise: recognising the word in the wild,
    /// then saying it.
    public static func from(_ item: SavedItem, surface: Surface) -> PictureRequest? {
        let written = Furigana.stripped(item.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty else { return nil }

        var accepted = [written]
        if let reading = item.reading, !reading.isEmpty { accepted.append(reading) }
        // A gloss is not a reading, so it is never accepted as one.
        return PictureRequest(
            targets: [written], accepted: accepted, surface: surface,
            sourceLabel: item.gloss.isEmpty ? written : "\(written) — \(item.gloss)")
    }

    /// Builds one from free text the learner typed.
    public static func from(text: String, surface: Surface) -> PictureRequest? {
        let written = Furigana.stripped(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty, written.count <= 12 else { return nil }
        return PictureRequest(
            targets: [written], accepted: [written], surface: surface,
            sourceLabel: written)
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
