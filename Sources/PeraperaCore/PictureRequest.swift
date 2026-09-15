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
            case .noren: "Brush on hanging cloth, mostly vertical, folded and angled."
            case .menuBoard: "Marker or brush on wood, everyday handwriting."
            case .stationSign: "Printed type. Closest to a screen."
            case .shopWindow: "Display lettering, reflections, at an angle."
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

        /// The place and material, without the lettering: that is rolled
        /// separately, so the same surface does not always read the same way.
        public func setting(language: String) -> String {
            switch self {
            case .enamelPlate:
                "A close-up photograph of an old weathered enamel metal sign "
                    + "bolted to a concrete wall, dark text on white, rust "
                    + "creeping in at the edges, daylight, slight angle."
            case .noren:
                "A photograph of a navy noren curtain hanging in a shop doorway, "
                    + "the text in white on the cloth, which is folded and "
                    + "moving slightly, warm afternoon light."
            case .menuBoard:
                "A close-up photograph of a handwritten menu board on wood "
                    + "inside a small restaurant, warm interior lighting."
            case .stationSign:
                "A photograph of a \(language) railway station sign, white "
                    + "board with dark lettering on a pole, platform blurred "
                    + "behind, daylight."
            case .shopWindow:
                "A photograph of a shop window poster, seen at an angle with a "
                    + "slight reflection in the glass, street visible behind, "
                    + "daylight."
            case .handwrittenNote:
                "A close-up photograph of a handwritten note on paper taped to "
                    + "a glass door, slightly creased paper, daylight."
            }
        }

        /// The letterings this surface is seen with. A station sign is never
        /// brushed; a noren is never in gothic type.
        public var letterings: [Lettering] {
            switch self {
            case .enamelPlate: [.gothic, .mincho, .kaisho]
            case .noren: [.kaisho, .gyosho, .edomoji]
            case .menuBoard: [.marker, .kaisho, .gyosho]
            case .stationSign: [.gothic, .mincho]
            case .shopWindow: [.gothic, .mincho, .edomoji, .stencil]
            case .handwrittenNote: [.ballpoint, .marker]
            }
        }

        /// Vertical twice on a noren: that is how they are mostly written,
        /// and the roll is uniform over the list.
        public var directions: [Direction] {
            switch self {
            case .stationSign: [.horizontal]
            case .noren: [.vertical, .vertical, .horizontal]
            default: [.horizontal, .vertical]
            }
        }
    }

    /// How the characters are formed. This is where a sign gets hard: the
    /// same word in gothic type and in running brush script are different
    /// reading tasks, and a scene that varies only the backdrop trains one.
    public enum Lettering: String, CaseIterable, Sendable {
        case gothic, mincho, kaisho, gyosho, edomoji, marker, ballpoint, stencil

        /// The prompt fragment.
        public var description: String {
            switch self {
            case .gothic: "clean printed gothic (sans-serif) type"
            case .mincho: "printed mincho (serif) type with thin horizontals"
            case .kaisho: "bold brush calligraphy in regular script (kaisho), thick confident strokes"
            case .gyosho: "flowing brush calligraphy in semi-cursive script (gyosho), strokes running into one another"
            case .edomoji: "thick rounded Edo-style display lettering (edomoji), strokes filling the space"
            case .marker: "natural everyday marker handwriting"
            case .ballpoint: "quick casual ballpoint handwriting"
            case .stencil: "stencilled letters with visible bridges"
            }
        }
    }

    /// Japanese is written both ways, and vertical text is where a learner
    /// used to screens stalls.
    public enum Direction: String, CaseIterable, Sendable {
        case horizontal, vertical

        public var description: String {
            switch self {
            case .horizontal: "horizontally, left to right"
            case .vertical: "vertically, top to bottom, in a single column"
            }
        }
    }

    /// One lettering and one direction this surface is seen with.
    public struct Style: Equatable, Sendable {
        public let lettering: Lettering
        public let direction: Direction

        public init(lettering: Lettering, direction: Direction) {
            self.lettering = lettering
            self.direction = direction
        }

        public static func roll(
            for surface: Surface,
            pick: (Int) -> Int = { Int.random(in: 0..<$0) }
        ) -> Style {
            Style(lettering: surface.letterings[pick(surface.letterings.count)],
                  direction: surface.directions[pick(surface.directions.count)])
        }
    }

    /// What the learner asked for: a surface, or the app's pick.
    ///
    /// Text in the wild does not announce what it is written on, and always
    /// choosing the familiar surface trains the surface as much as the word —
    /// which is why the pick is the default, and why a batch rolls it once per
    /// picture rather than once per batch.
    public enum SurfaceChoice: Hashable, Sendable {
        case surprise
        case only(Surface)

        public func surface(
            pick: ([Surface]) -> Surface = { $0.randomElement() ?? .stationSign }
        ) -> Surface {
            switch self {
            case .surprise: pick(Surface.allCases)
            case let .only(surface): surface
            }
        }

        public var label: String {
            switch self {
            case .surprise: "Surprise me"
            case let .only(surface): surface.label
            }
        }

        public var summary: String {
            switch self {
            case .surprise: "One of the \(Surface.allCases.count), chosen for each picture."
            case let .only(surface): surface.summary
            }
        }

        /// Ordered so the easier surfaces come first, after the pick.
        public static var all: [SurfaceChoice] {
            [.surprise] + Surface.allCases
                .sorted {
                    $0.difficulty == $1.difficulty
                        ? $0.label < $1.label : $0.difficulty < $1.difficulty
                }
                .map(SurfaceChoice.only)
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
    public let style: Style
    /// Where the words came from, for the library's provenance line.
    public let sourceLabel: String

    public init(
        targets: [String], accepted: [String], surface: Surface,
        style: Style? = nil, sourceLabel: String
    ) {
        self.targets = targets
        self.accepted = accepted
        self.surface = surface
        self.style = style ?? Style.roll(for: surface)
        self.sourceLabel = sourceLabel
    }

    /// The scene handed to the image model. The literal text and the framing
    /// are added by the pipeline, which also verifies the text came out right.
    public func scene(language: String) -> String {
        surface.setting(language: language)
            + " The text is written \(style.direction.description), in "
            + "\(style.lettering.description)."
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

    /// Whether what was typed reads the sign.
    ///
    /// Romaji is the natural way to answer at a keyboard, so it is matched
    /// against every kana form with `KanaRomaji.accepts`; kana or kanji typed
    /// through an IME are matched as written. Both, rather than converting the
    /// romaji to kana first: the converter would have to guess at ambiguities
    /// (づ/ず, おう/おお) that the matcher already resolves per word.
    public static func reads(_ typed: String, _ accepted: [String]) -> Bool {
        let given = Grader.normalize(typed)
        guard !given.isEmpty else { return false }
        if accepted.contains(where: { Grader.normalize($0) == given }) { return true }
        return accepted.contains {
            !KanaInput.containsKanji($0) && KanaRomaji.accepts(typed, for: $0)
        }
    }

    /// The kana reading among the accepted forms, for showing after an answer.
    /// The first one, so a katakana word reads back as katakana.
    public static func reading(among accepted: [String]) -> String? {
        accepted.first { !KanaInput.containsKanji($0) && !$0.isEmpty }
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

    /// Builds a request from a dictionary word.
    ///
    /// Unlike a saved word, a dictionary word is never converted between
    /// scripts: the list is large enough that a script is served by words
    /// actually written in it, and a hiragana rendering of コーヒー is a sign
    /// nobody has seen. Kanji is offered where the entry has an ordinary kanji
    /// spelling, which for a hiragana-read word is what a sign would say.
    public static func from(
        _ word: ReadingDrill.Word, surface: Surface, scripts: Scripts
    ) -> PictureRequest? {
        guard let shown = forms(of: word, scripts: scripts).randomElement() else { return nil }
        let written = word.kanji ?? word.text
        return PictureRequest(
            targets: [shown],
            accepted: acceptedForms(written: written, reading: word.text),
            surface: surface,
            sourceLabel: "\(written) — \(word.gloss)")
    }

    /// The forms of a dictionary word that the chosen scripts allow.
    public static func forms(of word: ReadingDrill.Word, scripts: Scripts) -> [String] {
        var out: [String] = []
        if scripts.contains(.kanji), let kanji = word.kanji {
            out.append(kanji)
        }
        let native: Scripts = word.script == "k" ? .katakana : .hiragana
        if scripts.contains(native) {
            out.append(word.text)
        }
        return out
    }

    /// The words a dictionary picture may be drawn from: the most frequent of
    /// each script asked for (see `ReadingDrill.mostFrequent`).
    ///
    /// Per script rather than overall, because the overall frequency list is
    /// newspaper Japanese and holds two katakana words in its first thousand,
    /// both place names. Asking for katakana should yield コーヒー, not 北京.
    public static func dictionaryPool(
        _ words: [ReadingDrill.Word], scripts: Scripts
    ) -> [ReadingDrill.Word] {
        var pool: [ReadingDrill.Word] = []
        if scripts.contains(.kanji) {
            pool += ReadingDrill.mostFrequent(words.filter { $0.kanji != nil }, script: .both)
        }
        if scripts.contains(.hiragana) {
            pool += ReadingDrill.mostFrequent(words, script: .hiragana)
        }
        if scripts.contains(.katakana) {
            pool += ReadingDrill.mostFrequent(words, script: .katakana)
        }
        var seen = Set<String>()
        return pool.filter { seen.insert($0.id).inserted }
    }

    /// Draws `count` pictures of words the learner is not told.
    ///
    /// The point of a picture is to be read; a word chosen from a menu has
    /// already been read. Every word in the pool has a form the scripts allow,
    /// so a draw yields a picture rather than a refusal.
    public static func fromDictionary(
        _ words: [ReadingDrill.Word], count: Int, surface: SurfaceChoice,
        scripts: Scripts, shuffle: ([ReadingDrill.Word]) -> [ReadingDrill.Word] = { $0.shuffled() }
    ) -> [PictureRequest] {
        let pool = dictionaryPool(words, scripts: scripts)
        return draw(count, from: shuffle(pool)) { from($0, surface: surface.surface(), scripts: scripts) }
    }

    /// The same, from the learner's own saved words.
    public static func fromSaved(
        _ items: [SavedItem], count: Int, surface: SurfaceChoice,
        scripts: Scripts, shuffle: ([SavedItem]) -> [SavedItem] = { $0.shuffled() }
    ) -> [PictureRequest] {
        draw(count, from: shuffle(items)) { from($0, surface: surface.surface(), scripts: scripts) }
    }

    /// The first `count` of the pool that make a request. Walking the whole
    /// pool rather than taking a prefix: with kanji switched off, the prefix
    /// might be all kanji-only entries and yield nothing.
    private static func draw<Word>(
        _ count: Int, from pool: [Word], _ build: (Word) -> PictureRequest?
    ) -> [PictureRequest] {
        var out: [PictureRequest] = []
        for word in pool where out.count < count {
            if let request = build(word) { out.append(request) }
        }
        return out
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
