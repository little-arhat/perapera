import CoreGraphics

/// Converting between AppKit's bottom-left origin and SwiftUI's top-left one.
///
/// A rect computed in an unflipped `NSView` and handed to SwiftUI unconverted
/// lands as far from its subject as the subject is from the bottom of the view.
/// It compiles, it draws nothing wrong, and the thing anchored to it appears
/// somewhere else entirely -- which is how a word popover shipped attached to a
/// point off the bottom of the screen.
public enum Geometry {
    public static func flippingVertically(_ rect: CGRect, inHeight height: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x,
               y: height - rect.origin.y - rect.height,
               width: rect.width, height: rect.height)
    }
}
