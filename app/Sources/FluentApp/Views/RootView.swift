import SwiftUI
import FluentCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var model = model

        ZStack {
            palette.background.ignoresSafeArea()

            switch model.screen {
            case .home:
                HomeView()
            case let .lesson(id):
                if let record = model.record(id: id) {
                    LessonPlayerView(record: record)
                } else {
                    missing
                }
            case .archive:
                ArchiveView()
            case .lists:
                ListsView()
            case let .debrief(id):
                if let record = model.record(id: id) {
                    DebriefView(record: record)
                } else {
                    missing
                }
            }

            if let status = model.statusMessage {
                WorkingOverlay(status: status)
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(
                   get: { model.error != nil },
                   set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    private var missing: some View {
        VStack(spacing: 12) {
            Text("That lesson isn't here any more.")
            Button("Back") { model.screen = .home }
        }
    }
}
