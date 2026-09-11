import CoreGraphics
import Testing
@testable import PeraperaCore

// The conversion that was missing. A word near the top of a tall view was
// anchored near the bottom, which inside a scroll view means off-screen — the
// popover was being presented and nobody could see it.

@Test func flippingMovesARectFromTheBottomOriginToTheTopOne() {
    // A 20-tall box sitting 380 up from the bottom of a 400-tall view is 0 from
    // the top.
    let box = CGRect(x: 10, y: 380, width: 50, height: 20)
    #expect(Geometry.flippingVertically(box, inHeight: 400)
            == CGRect(x: 10, y: 0, width: 50, height: 20))
}

@Test func flippingIsItsOwnInverse() {
    let box = CGRect(x: 3, y: 17, width: 40, height: 11)
    let once = Geometry.flippingVertically(box, inHeight: 200)
    #expect(Geometry.flippingVertically(once, inHeight: 200) == box)
}

@Test func flippingLeavesTheHorizontalAloneAndKeepsTheSize() {
    let box = CGRect(x: 7, y: 5, width: 30, height: 12)
    let flipped = Geometry.flippingVertically(box, inHeight: 100)
    #expect(flipped.origin.x == box.origin.x)
    #expect(flipped.size == box.size)
}
