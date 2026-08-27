// Generates Fluent.icns from code.
//
// Drawn rather than hand-authored so the icon is diffable, reproducible, and
// tweakable in one place. Run via `make icon`.
//
// Design: a Solarized-dark squircle, a speech bubble for "language as something
// spoken", and あ — the first character a Japanese learner meets. The bubble
// keeps it recognizable at 16pt where the glyph alone would smear.

import AppKit
import CoreText
import Foundation

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                    ? CommandLine.arguments[1] : ".")

// Solarized.
let base03 = NSColor(srgbRed: 0x00 / 255, green: 0x2B / 255, blue: 0x36 / 255, alpha: 1)
let base02 = NSColor(srgbRed: 0x07 / 255, green: 0x36 / 255, blue: 0x42 / 255, alpha: 1)
let base3  = NSColor(srgbRed: 0xFD / 255, green: 0xF6 / 255, blue: 0xE3 / 255, alpha: 1)
let blue   = NSColor(srgbRed: 0x26 / 255, green: 0x8B / 255, blue: 0xD2 / 255, alpha: 1)
let cyan   = NSColor(srgbRed: 0x2A / 255, green: 0xA1 / 255, blue: 0x98 / 255, alpha: 1)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let s = size
    // macOS icons sit inset inside their canvas rather than filling it.
    let inset = s * 0.055
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    // Apple's continuous-corner ratio.
    let squircle = NSBezierPath(roundedRect: rect,
                                xRadius: rect.width * 0.2237,
                                yRadius: rect.width * 0.2237)

    context.saveGState()
    squircle.addClip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [base02.cgColor, base03.cgColor] as CFArray,
        locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: [])
    }
    context.restoreGState()

    // Speech bubble: a rounded rect with a tail, in Solarized blue→cyan.
    let bubbleWidth = rect.width * 0.66
    let bubbleHeight = rect.height * 0.54
    let bubble = CGRect(
        x: rect.midX - bubbleWidth / 2,
        y: rect.midY - bubbleHeight / 2 + rect.height * 0.055,
        width: bubbleWidth, height: bubbleHeight)

    let bubblePath = NSBezierPath(roundedRect: bubble,
                                  xRadius: bubbleHeight * 0.28,
                                  yRadius: bubbleHeight * 0.28)
    // Tail, bottom-left, angled like a spoken aside.
    let tail = NSBezierPath()
    tail.move(to: CGPoint(x: bubble.minX + bubble.width * 0.20, y: bubble.minY + 1))
    tail.line(to: CGPoint(x: bubble.minX + bubble.width * 0.10,
                          y: bubble.minY - bubble.height * 0.26))
    tail.line(to: CGPoint(x: bubble.minX + bubble.width * 0.42, y: bubble.minY + 1))
    tail.close()
    bubblePath.append(tail)

    context.saveGState()
    bubblePath.addClip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [cyan.cgColor, blue.cgColor] as CFArray,
        locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bubble.minX, y: bubble.maxY),
            end: CGPoint(x: bubble.maxX, y: bubble.minY - bubble.height * 0.26),
            options: [])
    }
    context.restoreGState()

    // あ, centred in the bubble.
    let glyphSize = bubbleHeight * 0.72
    let font = NSFont(name: "HiraginoSans-W6", size: glyphSize)
        ?? NSFont(name: "HiraMaruProN-W4", size: glyphSize)
        ?? NSFont.systemFont(ofSize: glyphSize, weight: .semibold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: base3,
    ]
    let glyph = NSAttributedString(string: "あ", attributes: attributes)
    let glyphBounds = glyph.size()
    glyph.draw(at: NSPoint(
        x: bubble.midX - glyphBounds.width / 2,
        y: bubble.midY - glyphBounds.height / 2))

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, size: CGFloat) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])
}

let iconset = outputDir.appending(path: "Fluent.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The sizes iconutil expects.
let variants: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let image = drawIcon(size: variant.pixels)
    guard let data = png(image, size: variant.pixels) else {
        FileHandle.standardError.write(Data("failed: \(variant.name)\n".utf8))
        continue
    }
    try data.write(to: iconset.appending(path: "\(variant.name).png"))
}

print("wrote \(iconset.path)")
