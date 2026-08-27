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
                .solarized()
                .frame(minWidth: 720, minHeight: 520)
                .frame(
                    idealWidth: AppWindow.idealSize.width,
                    idealHeight: AppWindow.idealSize.height)
                .task { await model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(AppWindow.idealSize)

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
