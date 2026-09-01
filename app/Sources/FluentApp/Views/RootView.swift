import SwiftUI
import FluentCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(selection: sectionBinding) {
                ForEach(AppModel.Section.allCases) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
        } detail: {
            VStack(spacing: 0) {
                ZStack {
                    palette.background
                    content
                    if let status = model.statusMessage {
                        WorkingOverlay(status: status)
                    }
                }
                Divider()
                SpendFooter()
            }
            .ignoresSafeArea(edges: .top)
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

    /// Selecting a row navigates; the reverse mapping keeps the highlight
    /// correct when the app moves itself, as it does after generating a lesson.
    private var sectionBinding: Binding<AppModel.Section?> {
        Binding(
            get: { model.section },
            set: { if let new = $0 { model.show(new) } })
    }

    @ViewBuilder
    private var content: some View {
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
        case .images:
            ImagesView()
        case let .debrief(id):
            if let record = model.record(id: id) {
                DebriefView(record: record)
            } else {
                missing
            }
        }
    }

    private var missing: some View {
        VStack(spacing: 12) {
            Text("That lesson isn't here any more.")
            Button("Back") { model.screen = .home }
        }
    }
}
