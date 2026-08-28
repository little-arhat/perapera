import AppKit
import CoreText
import NaturalLanguage
import SwiftUI
import FluentCore

/// Target-language text with real furigana, arbitrary selection, and word
/// highlighting on hover.
///
/// The SwiftUI-only version split the string into one `Text` per segment inside
/// a `FlowLayout`, because SwiftUI has no ruby. That rendered correctly and
/// broke everything else: selection cannot span separate `Text` views, so the
/// learner could only ever select one fragment — which felt like "selectable by
/// kanji only", because the fragments *are* the kanji runs.
///
/// Core Text does have ruby (`CTRubyAnnotation`), and it keeps the line as one
/// attributed string, so selection is a range over real text. `NSTextView`
/// silently drops ruby annotations — verified — so this draws with Core Text
/// directly and implements selection over the resulting frame.
///
/// The ruby is an *annotation*, not inline text, so a copied selection contains
/// 切符 rather than 切符[きっぷ]: the reading is displayed without polluting the
/// clipboard.
struct RubyTextView: NSViewRepresentable {
    let annotated: String
    let showFurigana: Bool
    let fontSize: CGFloat
    let color: NSColor
    let rubyColor: NSColor
    let selectable: Bool
    let highlightWords: Bool
    /// Width to lay out into. SwiftUI measures after layout, so the view needs
    /// telling rather than asking.
    let availableWidth: CGFloat
    var isMarkdown: Bool = false

    func makeNSView(context: Context) -> RubyCanvas {
        let view = RubyCanvas()
        view.configure(with: model)
        return view
    }

    func updateNSView(_ view: RubyCanvas, context: Context) {
        view.configure(with: model)
    }

    @MainActor
    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: RubyCanvas, context: Context
    ) -> CGSize? {
        // A nil proposal means "unconstrained"; falling through to zero would
        // lay every character onto its own line.
        let width = proposal.width ?? (availableWidth > 0 ? availableWidth : 600)
        return nsView.fittingSize(width: max(width, 80))
    }

    private var model: RubyCanvas.Model {
        .init(
            annotated: annotated,
            showFurigana: showFurigana,
            fontSize: fontSize,
            color: color,
            rubyColor: rubyColor,
            selectable: selectable,
            highlightWords: highlightWords,
            isMarkdown: isMarkdown
        )
    }
}

/// The drawing and interaction. An NSView because Core Text needs a graphics
/// context and selection needs mouse events, neither of which SwiftUI exposes.
final class RubyCanvas: NSView {
    struct Model: Equatable {
        var annotated: String
        var showFurigana: Bool
        var fontSize: CGFloat
        var color: NSColor
        var rubyColor: NSColor
        var selectable: Bool
        var highlightWords: Bool
        /// Parse the source as Markdown before applying ruby.
        ///
        /// Explanatory prose — a lesson preamble, a feedback comment — carries
        /// bold and italics. Rendering it as plain text would lose them;
        /// rendering it with SwiftUI Markdown loses ruby. Doing both here keeps
        /// the formatting *and* keeps the line length constant when readings
        /// toggle, which is what stops the page reflowing.
        var isMarkdown: Bool = false
    }

    private var model = Model(
        annotated: "", showFurigana: false, fontSize: 22,
        color: .labelColor, rubyColor: .secondaryLabelColor,
        selectable: false, highlightWords: false)

    private var attributed = NSAttributedString()
    /// Whether any segment carries a reading. Drives layout regardless of
    /// whether readings are currently shown.
    private var hasRuby = false
    /// Offsets in `attributed` mapped back to the plain (unannotated) string, so
    /// a selection can be copied without markup.
    private var plainText = ""
    private var frame_: CTFrame?
    private var lines: [(line: CTLine, origin: CGPoint)] = []

    private var selection: Range<Int>?
    private var anchor: Int?
    private var hoveredWord: Range<Int>?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { model.selectable }

    /// Height depends on width, and the width SwiftUI finally allots need not
    /// be the one it proposed while measuring. Without re-measuring on resize,
    /// a string that wraps in the real slot but not in the proposed one is laid
    /// out for one line and clipped — which is why only the longest item looked
    /// wrong.
    override var intrinsicContentSize: NSSize {
        guard bounds.width > 1 else { return NSSize(width: NSView.noIntrinsicMetric,
                                                    height: NSView.noIntrinsicMetric) }
        return fittingSize(width: bounds.width)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - bounds.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    func configure(with model: Model) {
        guard model != self.model else { return }
        let highlightingChanged = model.highlightWords != self.model.highlightWords
        self.model = model
        if !model.selectable { selection = nil }
        if !model.highlightWords { hoveredWord = nil }
        rebuild()
        // Tracking areas are rebuilt on bounds changes, but toggling word
        // highlighting changes nothing about the bounds -- without this the
        // toggle does nothing until the view happens to resize.
        if highlightingChanged { updateTrackingAreas() }
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A window does not deliver mouseMoved unless it is asked to, and it
        // defaults to off -- so hover silently did nothing.
        window?.acceptsMouseMovedEvents = true
        updateTrackingAreas()
    }

    // MARK: - Text

    private func rebuild() {
        if model.isMarkdown {
            rebuildFromMarkdown()
            return
        }
        let segments = Furigana.parse(model.annotated)
        plainText = segments.map(\.base).joined()
        hasRuby = segments.contains { $0.reading != nil }

        let font = NSFont(name: "HiraginoSans-W3", size: model.fontSize)
            ?? NSFont.systemFont(ofSize: model.fontSize)
        let result = NSMutableAttributedString()

        for segment in segments {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: model.color,
            ]
            // The annotation is always attached; hiding readings only makes it
            // transparent. Attaching it conditionally changed the line's ascent,
            // so toggling readings moved every line on the page — and reserving
            // headroom is not enough to prevent that, because the metrics
            // themselves differ. Clipboard content is unaffected either way:
            // copying reads `plainText`, which is built from the base segments.
            if let reading = segment.reading {
                let color = model.showFurigana ? model.rubyColor : NSColor.clear
                attributes[kCTRubyAnnotationAttributeName as NSAttributedString.Key] =
                    CTRubyAnnotationCreateWithAttributes(
                        .auto, .auto, .before, reading as CFString,
                        [
                            kCTRubyAnnotationSizeFactorAttributeName: 0.5,
                            kCTForegroundColorAttributeName: color.cgColor,
                        ] as CFDictionary
                    )
            }
            result.append(NSAttributedString(string: segment.base, attributes: attributes))
        }
        attributed = result
        frame_ = nil
    }

    /// Markdown first, then ruby.
    ///
    /// Order matters and works out: a bare `[きっぷ]` is not link syntax, so it
    /// survives Markdown parsing intact and can be converted afterwards. Going
    /// the other way — ruby first — would leave the annotations to be mangled
    /// by the Markdown parser.
    private func rebuildFromMarkdown() {
        var options = AttributedString.MarkdownParsingOptions()
        // Full syntax would swallow the "- " and "> " prefixes into list and
        // quote structures Core Text will not draw, silently dropping them.
        // Inline-only keeps them as the literal characters they already appear
        // as elsewhere in the app.
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace

        let parsed = (try? NSAttributedString(markdown: model.annotated, options: options))
            ?? NSAttributedString(string: model.annotated)
        let result = NSMutableAttributedString(attributedString: parsed)

        let base = NSFont(name: "HiraginoSans-W3", size: model.fontSize)
            ?? NSFont.systemFont(ofSize: model.fontSize)
        let full = NSRange(location: 0, length: result.length)
        result.addAttributes([.font: base, .foregroundColor: model.color], range: full)

        // Markdown records emphasis as an intent rather than a font, so the
        // traits have to be applied by hand.
        result.enumerateAttribute(
            .inlinePresentationIntent, in: full
        ) { value, range, _ in
            guard let raw = value as? UInt else { return }
            let intent = InlinePresentationIntent(rawValue: raw)
            var traits: NSFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            guard !traits.isEmpty else { return }
            // Japanese faces generally ship no italic, so asking Hiragino for
            // one yields nil and the emphasis is silently lost. Fall back to
            // the system font, which has both traits — the run is almost always
            // latin prose anyway, since Japanese does not italicise.
            let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
            let styled = NSFont(descriptor: descriptor, size: model.fontSize)
                ?? NSFont(
                    descriptor: NSFont.systemFont(ofSize: model.fontSize)
                        .fontDescriptor.withSymbolicTraits(traits),
                    size: model.fontSize)
            if let styled {
                result.addAttribute(.font, value: styled, range: range)
            }
        }

        hasRuby = applyRuby(to: result)
        plainText = result.string
        attributed = result
        frame_ = nil
    }

    /// Turns `漢字[かんじ]` markers inside an attributed string into real ruby.
    ///
    /// Walks backwards so that removing a marker cannot invalidate the indices
    /// of the ones still to be processed.
    @discardableResult
    private func applyRuby(to text: NSMutableAttributedString) -> Bool {
        let pattern = try? NSRegularExpression(pattern: "\\[([^\\[\\]]{1,12})\\]")
        guard let pattern else { return false }
        let matches = pattern.matches(
            in: text.string, range: NSRange(location: 0, length: text.length))
        var applied = false

        for match in matches.reversed() {
            let markerRange = match.range
            let readingRange = match.range(at: 1)
            let reading = (text.string as NSString).substring(with: readingRange)

            let baseLength = trailingKanjiCount(
                in: text.string as NSString, before: markerRange.location)
            guard baseLength > 0 else { continue }
            let baseRange = NSRange(
                location: markerRange.location - baseLength, length: baseLength)

            let color = model.showFurigana ? model.rubyColor : NSColor.clear
            let annotation = CTRubyAnnotationCreateWithAttributes(
                .auto, .auto, .before, reading as CFString,
                [
                    kCTRubyAnnotationSizeFactorAttributeName: 0.5,
                    kCTForegroundColorAttributeName: color.cgColor,
                ] as CFDictionary)
            text.addAttribute(
                kCTRubyAnnotationAttributeName as NSAttributedString.Key,
                value: annotation, range: baseRange)
            text.deleteCharacters(in: markerRange)
            applied = true
        }
        return applied
    }

    private func trailingKanjiCount(in text: NSString, before index: Int) -> Int {
        var count = 0
        var cursor = index - 1
        while cursor >= 0 {
            let scalar = text.character(at: cursor)
            let isKanji = (0x4E00...0x9FFF).contains(Int(scalar))
                || (0x3400...0x4DBF).contains(Int(scalar))
                || Int(scalar) == 0x3005
            guard isKanji else { break }
            count += 1
            cursor -= 1
        }
        return count
    }

    func fittingSize(width: CGFloat) -> CGSize {
        guard !attributed.string.isEmpty else { return CGSize(width: width, height: 0) }
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        var fitRange = CFRange()
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), &fitRange)
        // Ruby sits above the line and is not counted in the suggested height,
        // so a line with readings would be clipped at the top without this.
        // Independent of the toggle, so the height never changes with it.
        let rubyHeadroom = hasRuby ? model.fontSize * 0.6 : 0
        return CGSize(width: width, height: ceil(size.height + rubyHeadroom + 2))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        ensureFrameForCurrentBounds()
        guard let frame = frame_ else { return }

        // Core Text lays out from the top of the path; the view is unflipped,
        // so shift so the first line sits at the top with room for its ruby.
        let headroom = hasRuby ? model.fontSize * 0.6 : 0
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height - textHeight - headroom)

        if let hoveredWord, model.highlightWords {
            fill(range: hoveredWord, color: NSColor.systemBlue.withAlphaComponent(0.14),
                 context: context)
        }
        if let selection, !selection.isEmpty {
            fill(range: selection, color: NSColor.selectedTextBackgroundColor,
                 context: context)
        }

        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private var textHeight: CGFloat = 0

    private func ensureFrameForCurrentBounds() {
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        var fitRange = CFRange()
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil,
            CGSize(width: bounds.width, height: .greatestFiniteMagnitude), &fitRange)
        textHeight = size.height

        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: bounds.width, height: max(size.height, 1)),
            transform: nil)
        let frame = CTFramesetterCreateFrame(
            setter, CFRange(location: 0, length: 0), path, nil)
        frame_ = frame
        let ctLines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
        var origins = [CGPoint](repeating: .zero, count: ctLines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        lines = Array(zip(ctLines, origins))
    }

    /// Paints the rectangles covering a character range, line by line.
    private func fill(range: Range<Int>, color: NSColor, context: CGContext) {
        context.saveGState()
        color.setFill()
        for (line, origin) in lines {
            let lineRange = CTLineGetStringRange(line)
            let start = lineRange.location
            let end = start + lineRange.length
            let from = max(range.lowerBound, start)
            let to = min(range.upperBound, end)
            guard from < to else { continue }

            let x1 = CTLineGetOffsetForStringIndex(line, from, nil)
            let x2 = CTLineGetOffsetForStringIndex(line, to, nil)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let rect = CGRect(
                x: origin.x + min(x1, x2),
                y: origin.y - descent,
                width: abs(x2 - x1),
                height: ascent + descent)
            context.fill(rect.insetBy(dx: 0, dy: -1))
        }
        context.restoreGState()
    }

    // MARK: - Hit testing

    /// Character index under a point in view coordinates.
    private func characterIndex(at point: NSPoint) -> Int? {
        let headroom = hasRuby ? model.fontSize * 0.6 : 0
        let adjusted = CGPoint(
            x: point.x, y: point.y - (bounds.height - textHeight - headroom))
        for (line, origin) in lines {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let top = origin.y + ascent
            let bottom = origin.y - descent
            guard adjusted.y <= top, adjusted.y >= bottom else { continue }
            let index = CTLineGetStringIndexForPosition(
                line, CGPoint(x: adjusted.x - origin.x, y: 0))
            return index == kCFNotFound ? nil : index
        }
        return nil
    }

    /// The word containing an index, using the system's Japanese segmenter.
    ///
    /// `NLTokenizer` handles Japanese, which has no spaces — 切符を2枚ください
    /// segments to 切符 | を | 2 | 枚 | ください. It is imperfect on compounds
    /// (新幹線 comes back as 新 + 幹線) but far better than splitting on script
    /// changes, and it makes particles individually hoverable, which is exactly
    /// what a learner wants to isolate.
    private func wordRange(containing index: Int) -> Range<Int>? {
        guard !plainText.isEmpty else { return nil }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = plainText
        guard let position = utf16Index(index) else { return nil }
        let tokenRange = tokenizer.tokenRange(at: position)
        guard !tokenRange.isEmpty else { return nil }
        let lower = plainText.utf16.distance(
            from: plainText.utf16.startIndex, to: tokenRange.lowerBound.samePosition(in: plainText.utf16) ?? plainText.utf16.startIndex)
        let upper = plainText.utf16.distance(
            from: plainText.utf16.startIndex, to: tokenRange.upperBound.samePosition(in: plainText.utf16) ?? plainText.utf16.startIndex)
        return lower..<upper
    }

    private func utf16Index(_ offset: Int) -> String.Index? {
        guard offset >= 0, offset <= plainText.utf16.count else { return nil }
        let utf16Position = plainText.utf16.index(
            plainText.utf16.startIndex, offsetBy: offset)
        return utf16Position.samePosition(in: plainText)
    }

    private func text(in range: Range<Int>) -> String {
        guard let lower = utf16Index(range.lowerBound),
              let upper = utf16Index(range.upperBound),
              lower <= upper
        else { return "" }
        return String(plainText[lower..<upper])
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        guard model.highlightWords else { return }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
            owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard model.highlightWords else { return }
        let point = convert(event.locationInWindow, from: nil)
        let word = characterIndex(at: point).flatMap(wordRange(containing:))
        if word != hoveredWord {
            hoveredWord = word
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredWord != nil {
            hoveredWord = nil
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard model.selectable || model.highlightWords else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = characterIndex(at: point) else { return }

        // A click takes the word; a drag takes a range. Copying the word on a
        // single click is the dictionary-lookup gesture, and it costs nothing
        // because a click that turns into a drag replaces the selection anyway.
        if event.clickCount == 1, let word = wordRange(containing: index) {
            selection = word
            copySelection()
        }
        anchor = index
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard model.selectable, let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = characterIndex(at: point) else { return }
        selection = min(anchor, index)..<max(anchor, index)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        // A completed drag copies, matching the click-to-copy gesture: the
        // point of selecting here is almost always a dictionary lookup.
        guard model.selectable, let selection, !selection.isEmpty else { return }
        copySelection()
    }

    private func copySelection() {
        guard let selection, !selection.isEmpty else { return }
        let copied = text(in: selection)
        guard !copied.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copied, forType: .string)
    }

    @objc func copy(_ sender: Any?) { copySelection() }

    override func keyDown(with event: NSEvent) {
        // ⌘C, and Escape to clear.
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "c" {
            copySelection()
            return
        }
        if event.keyCode == 53 {
            selection = nil
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }
}
