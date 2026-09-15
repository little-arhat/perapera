import Testing
@testable import PeraperaCore

// The script toggles decide what a sign is allowed to say. Getting them wrong
// means either an impossible request (kanji off, but only kanji available) or
// an answer marked wrong for being written in the other kana.

private let ticket = SavedItem(
    content: "切符", gloss: "ticket", kind: .word, sourceLessonId: nil,
    reading: "きっぷ")

@Test func kanaConversionIsAShiftAndLeavesTheRestAlone() {
    #expect(KanaInput.convertKana("きっぷ", to: .katakana) == "キップ")
    #expect(KanaInput.convertKana("キップ", to: .hiragana) == "きっぷ")
    // Kanji, latin and punctuation pass through, which is what makes it safe
    // to run over a whole phrase.
    #expect(KanaInput.convertKana("切符を2枚", to: .katakana) == "切符ヲ2枚")
    #expect(KanaInput.convertKana("コーヒー", to: .katakana) == "コーヒー")
}

@Test func eachScriptOffersItsOwnForm() {
    #expect(PictureRequest.forms(written: "切符", reading: "きっぷ", scripts: .kanji)
            == ["切符"])
    #expect(PictureRequest.forms(written: "切符", reading: "きっぷ", scripts: .hiragana)
            == ["きっぷ"])
    #expect(PictureRequest.forms(written: "切符", reading: "きっぷ", scripts: .katakana)
            == ["キップ"])
}

@Test func aFormIsOfferedOnlyWhenItCanActuallyBeMade() {
    // No reading, so the kana forms cannot be invented from the characters.
    #expect(PictureRequest.forms(written: "切符", reading: nil, scripts: .hiragana).isEmpty)
    // A word already in kana has no kanji form.
    #expect(PictureRequest.forms(written: "ください", reading: nil, scripts: .kanji).isEmpty)
}

@Test func duplicateFormsAreNotOfferedTwice() {
    // A hiragana word with both kana scripts on would otherwise yield the same
    // string twice and skew the random pick.
    let forms = PictureRequest.forms(
        written: "ください", reading: nil, scripts: [.hiragana, .katakana])
    #expect(forms.count == 2)
    #expect(Set(forms).count == 2)
}

@Test func everyWritingOfTheWordIsAcceptedWhicheverIsShown() {
    // The learner is reading the word. Answering キップ to a hiragana sign is
    // not a mistake, and marking it one would be the app's error.
    let request = PictureRequest.from(ticket, surface: .enamelPlate, scripts: .katakana)
    let accepted = try! #require(request?.accepted)
    #expect(accepted.contains("切符"))
    #expect(accepted.contains("きっぷ"))
    #expect(accepted.contains("キップ"))
}

@Test func anImpossibleRequestIsRefusedNotFudged() {
    // Kanji switched off, and only a kanji form available: there is nothing
    // honest to put on the sign, so no request is made rather than one that
    // ignores the setting.
    let noReading = SavedItem(
        content: "駐車場", gloss: "car park", kind: .word, sourceLessonId: nil)
    #expect(PictureRequest.from(noReading, surface: .enamelPlate,
                                scripts: [.hiragana, .katakana]) == nil)
    #expect(PictureRequest.from(text: "駐車場", surface: .enamelPlate,
                                scripts: .hiragana) == nil)
}

@Test func theShownFormRespectsTheSelection() {
    for _ in 0..<20 {
        let request = PictureRequest.from(
            ticket, surface: .noren, scripts: [.hiragana, .katakana])
        let shown = try! #require(request?.targets.first)
        #expect(shown == "きっぷ" || shown == "キップ", "showed \(shown)")
    }
}

@Test func surfacesAreOrderedEasiestFirstAfterThePick() {
    // A beginner should not be offered handwriting before a station sign, and
    // the app's own pick comes first because it is the default.
    let ordered = PictureRequest.SurfaceChoice.all
    #expect(ordered.first == .surprise)
    #expect(ordered.dropFirst().first == .only(.stationSign))
    #expect(ordered.last == .only(.handwrittenNote))
    #expect(ordered.count == PictureRequest.Surface.allCases.count + 1)
}

@Test func surpriseChoosesFromEverySurface() {
    // Every surface has to be reachable, or "surprise me" quietly means "one of
    // the three I already read comfortably".
    var chosen: Set<PictureRequest.Surface> = []
    for index in PictureRequest.Surface.allCases.indices {
        chosen.insert(PictureRequest.SurfaceChoice.surprise.surface { $0[index] })
    }
    #expect(chosen.count == PictureRequest.Surface.allCases.count)
    #expect(PictureRequest.SurfaceChoice.only(.noren).surface { _ in .menuBoard } == .noren)
}

// Dictionary words. The learner is not told the word, so the request has to
// be right without them checking it.

private let anzen = ReadingDrill.Word(w: "あんぜん", g: "safety", s: "h", t: 1, f: 1, k: "安全")
private let coffee = ReadingDrill.Word(w: "コーヒー", g: "coffee", s: "k", t: 1, f: 3)
private let kudasai = ReadingDrill.Word(w: "ください", g: "please", s: "h", t: 1, f: 2)

@Test func aDictionaryWordIsShownInItsOwnScriptOrItsKanji() {
    #expect(PictureRequest.forms(of: anzen, scripts: .all) == ["安全", "あんぜん"])
    #expect(PictureRequest.forms(of: anzen, scripts: .kanji) == ["安全"])
    // Never converted: a hiragana コーヒー is a sign nobody has seen.
    #expect(PictureRequest.forms(of: coffee, scripts: .hiragana).isEmpty)
    #expect(PictureRequest.forms(of: coffee, scripts: .katakana) == ["コーヒー"])
    // No kanji form, so kanji-only has nothing to show.
    #expect(PictureRequest.forms(of: kudasai, scripts: .kanji).isEmpty)
}

@Test func aDictionaryWordAcceptsEveryWritingOfItself() {
    let request = try! #require(PictureRequest.from(anzen, surface: .noren, scripts: .kanji))
    #expect(request.targets == ["安全"])
    #expect(request.accepted.contains("あんぜん"))
    #expect(request.accepted.contains("アンゼン"))
    #expect(request.sourceLabel == "安全 — safety")
}

@Test func theDictionaryPoolServesEachScriptFromItsOwnFrequencyList() {
    // Two hundred common kanji words and three katakana ones: asking for
    // katakana must reach the three, not draw blanks from the kanji majority.
    let kanjiWords = (1...200).map {
        ReadingDrill.Word(w: "か\($0)", g: "g", s: "h", t: 1, f: 1, k: "漢\($0)")
    }
    let katakana = ["コーヒー", "ビール", "パン"].map {
        ReadingDrill.Word(w: $0, g: "g", s: "k", t: 1, f: 40)
    }
    let words = kanjiWords + katakana
    #expect(PictureRequest.dictionaryPool(words, scripts: .katakana).map(\.text)
            == katakana.map(\.text))
    #expect(PictureRequest.dictionaryPool(words, scripts: .kanji).count == 200)
    // A word in two lists appears once.
    #expect(PictureRequest.dictionaryPool(words, scripts: .all).count == 203)
}

@Test func aDrawSkipsWordsTheScriptsCannotShowRatherThanComingUpShort() {
    // Three requested, kanji only, and the first two of the shuffled pool have
    // no kanji: the draw walks on to find three, and every one is kanji.
    let words = [kudasai, coffee, anzen,
                 ReadingDrill.Word(w: "いみ", g: "meaning", s: "h", t: 1, f: 1, k: "意味"),
                 ReadingDrill.Word(w: "いけん", g: "opinion", s: "h", t: 1, f: 1, k: "意見")]
    let drawn = PictureRequest.fromDictionary(
        words, count: 3, surface: .only(.enamelPlate), scripts: .kanji, shuffle: { $0 })
    #expect(drawn.map(\.targets) == [["安全"], ["意味"], ["意見"]])
    #expect(drawn.allSatisfy { $0.surface == .enamelPlate })
}

@Test func aBatchRollsTheSurfacePerPictureNotPerBatch() {
    // Ten pictures on one surface is a lesson in that surface. With every
    // surface equally likely, ten identical rolls happen once in 8,000 runs.
    let words = (1...10).map {
        ReadingDrill.Word(w: "か\($0)", g: "g", s: "h", t: 1, f: 1, k: "漢\($0)")
    }
    let drawn = PictureRequest.fromDictionary(
        words, count: 10, surface: .surprise, scripts: .kanji, shuffle: { $0 })
    #expect(drawn.count == 10)
    #expect(Set(drawn.map(\.surface)).count > 1)
}

@Test func savedWordsAreDrawnHiddenToo() {
    let items = [ticket,
                 SavedItem(content: "駐車場", gloss: "car park", kind: .word, sourceLessonId: nil)]
    // Kana only: the entry without a reading cannot be shown and is passed over.
    let drawn = PictureRequest.fromSaved(
        items, count: 2, surface: .only(.noren), scripts: [.hiragana, .katakana], shuffle: { $0 })
    #expect(drawn.count == 1)
    #expect(drawn.first?.accepted.contains("切符") == true)
}

// Lettering. The reading difficulty is in how the characters are formed, so a
// surface rolls its lettering and direction rather than always reading the
// same way.

@Test func everySurfaceHasLetteringsItIsActuallySeenWith() {
    for surface in PictureRequest.Surface.allCases {
        #expect(!surface.letterings.isEmpty, "\(surface) has no lettering")
        #expect(!surface.directions.isEmpty, "\(surface) has no direction")
    }
    // A station sign is printed and horizontal; a noren is never in gothic type.
    #expect(PictureRequest.Surface.stationSign.directions == [.horizontal])
    #expect(!PictureRequest.Surface.stationSign.letterings.contains(.kaisho))
    #expect(!PictureRequest.Surface.noren.letterings.contains(.gothic))
    #expect(PictureRequest.Surface.noren.directions.contains(.vertical))
}

@Test func aRollStaysWithinWhatTheSurfaceAllows() {
    for surface in PictureRequest.Surface.allCases {
        for _ in 0..<20 {
            let style = PictureRequest.Style.roll(for: surface)
            #expect(surface.letterings.contains(style.lettering))
            #expect(surface.directions.contains(style.direction))
        }
    }
    // The injected pick reaches the last entry, not just the first.
    let last = PictureRequest.Style.roll(for: .shopWindow) { $0 - 1 }
    #expect(last.lettering == .stencil)
    #expect(last.direction == .vertical)
}

@Test func theSceneSaysHowTheTextIsWritten() {
    let request = PictureRequest(
        targets: ["安全"], accepted: ["安全", "あんぜん"], surface: .noren,
        style: .init(lettering: .gyosho, direction: .vertical), sourceLabel: "安全")
    let scene = request.scene(language: "Japanese")
    #expect(scene.contains("noren"))
    #expect(scene.contains("vertically"))
    #expect(scene.contains("gyosho"))
    // The setting no longer decides the lettering: the same surface can come
    // out in a different hand.
    let other = PictureRequest(
        targets: ["安全"], accepted: ["安全"], surface: .noren,
        style: .init(lettering: .kaisho, direction: .horizontal), sourceLabel: "安全")
    #expect(other.scene(language: "Japanese") != scene)
}

// Answering. Romaji at a keyboard, kana or kanji through an IME: all read the
// sign, and nothing else does.

@Test func romajiReadsTheSignAndSoDoesKanaOrKanji() {
    let accepted = ["安全", "あんぜん", "アンゼン"]
    #expect(PictureRequest.reads("anzen", accepted))
    #expect(PictureRequest.reads("ANZEN ", accepted))
    #expect(PictureRequest.reads("あんぜん", accepted))
    #expect(PictureRequest.reads("安全", accepted))
    #expect(!PictureRequest.reads("anzon", accepted))
    #expect(!PictureRequest.reads("", accepted))
    // Long vowels however the learner spells them.
    let coffee = ["コーヒー", "こーひー"]
    #expect(PictureRequest.reads("koohii", coffee))
    #expect(PictureRequest.reads("kōhī", coffee))
    #expect(!PictureRequest.reads("kohi", coffee))
}

@Test func theReadingShownIsTheFirstKanaFormSoKatakanaStaysKatakana() {
    #expect(PictureRequest.reading(among: ["安全", "あんぜん", "アンゼン"]) == "あんぜん")
    #expect(PictureRequest.reading(among: ["コーヒー", "こーひー"]) == "コーヒー")
    #expect(PictureRequest.reading(among: ["駐車場"]) == nil)
}
