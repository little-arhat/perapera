import SwiftUI

/// A photograph from disk, decoded once.
///
/// `NSImage(contentsOf:)` in a `body` decodes the file on every redraw, which
/// with a text field on the same screen means on every keystroke. The decode
/// happens once per URL here, off the render path.
struct PhotoView: View {
    let url: URL?
    var contentMode: ContentMode = .fit

    @State private var picture: NSImage?

    var body: some View {
        Group {
            if let picture {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            picture = url.flatMap(NSImage.init(contentsOf:))
        }
    }
}
