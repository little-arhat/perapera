import AppKit
import SwiftUI

@main
struct FluentApp: App {
    @State private var model = AppModel()
    @State private var speech = Speech()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(speech)
                .environment(\.textScale, model.textScale)
                .solarized()
                .frame(minWidth: 720, minHeight: 520)
                .frame(
                    idealWidth: AppWindow.idealSize.width,
                    idealHeight: AppWindow.idealSize.height)
                .task { await model.start() }
                // The title bar is not decoration: it carries double-click to
                // zoom, the window menu, and a drag region the content cannot
                // swallow. Hiding it traded those for a slightly cleaner edge,
                // which was a bad trade on macOS.
                .navigationTitle(model.windowTitle)
        }
        .defaultSize(AppWindow.idealSize)
        .commands { TextSizeCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
                .solarized()
        }
    }
}


/// Opening window size: most of the screen, because lesson prompts and
/// reorder tokens both want width, and 720pt forced wrapping mid-sentence.
enum AppWindow {
    static var idealSize: CGSize {
        guard let screen = NSScreen.main?.visibleFrame else {
            return CGSize(width: 1280, height: 860)
        }
        return CGSize(width: screen.width * 0.8, height: screen.height * 0.8)
    }
}
