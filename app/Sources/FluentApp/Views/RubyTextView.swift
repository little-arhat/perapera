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
            highlightWords: highlightWords
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
    }

    private var model = Model(
        annotated: "", showFurigana: false, fontSize: 22,
        color: .labelColor, rubyColor: .secondaryLabelColor,
        selectable: false, highlightWords: false)

    private var attributed = NSAttributedString()
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

    func configure(with model: Model) {
        guard model != self.model else { return }
        self.model = model
        if !model.selectable { selection = nil }
        if !model.highlightWords { hoveredWord = nil }
        rebuild()
        needsDisplay = true
    }

    // MARK: - Text

    private func rebuild() {
        let segments = Furigana.parse(model.annotated)
        plainText = segments.map(\.base).joined()

        let font = NSFont(name: "HiraginoSans-W3", size: model.fontSize)
            ?? NSFont.systemFont(ofSize: model.fontSize)
        let result = NSMutableAttributedString()

        for segment in segments {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: model.color,
            ]
            // Ruby is attached only when readings are shown. Attaching it
            // always and hiding it with colour would still reserve the space,
            // which is fine, but it would also put the reading on the clipboard
            // in some copy paths.
            if model.showFurigana, let reading = segment.reading {
                attributes[kCTRubyAnnotationAttributeName as NSAttributedString.Key] =
                    CTRubyAnnotationCreateWithAttributes(
                        .auto, .auto, .before, reading as CFString,
                        [
                            kCTRubyAnnotationSizeFactorAttributeName: 0.5,
                            kCTForegroundColorAttributeName: model.rubyColor.cgColor,
                        ] as CFDictionary
                    )
            }
            result.append(NSAttributedString(string: segment.base, attributes: attributes))
        }
        attributed = result
        frame_ = nil
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
        let rubyHeadroom = model.showFurigana ? model.fontSize * 0.6 : 0
        return CGSize(width: width, height: ceil(size.height + rubyHeadroom + 2))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        ensureFrameForCurrentBounds()
        guard let frame = frame_ else { return }

        // Core Text lays out from the top of the path; the view is unflipped,
        // so shift so the first line sits at the top with room for its ruby.
        let headroom = model.showFurigana ? model.fontSize * 0.6 : 0
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
        let headroom = model.showFurigana ? model.fontSize * 0.6 : 0
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
