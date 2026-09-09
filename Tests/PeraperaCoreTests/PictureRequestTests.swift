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

@Test func surfacesAreOrderedEasiestFirst() {
    // A beginner should not be offered handwriting before a station sign.
    let ordered = PictureRequest.surfaces
    #expect(ordered.first == .stationSign)
    #expect(ordered.last == .handwrittenNote)
}
