import SwiftUI
import PeraperaCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(selection: sectionBinding) {
                ProfileSwitcher()
                    .padding(.bottom, 4)
                ForEach(AppModel.Section.allCases) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
        } detail: {
            VStack(spacing: 0) {
                ZStack {
                    content
                    if let status = model.statusMessage {
                        WorkingOverlay(status: status)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                SpendFooter()
            }
            // Only the background reaches under the title bar. Extending the
            // *content* there — which is what adding the footer did — slid the
            // first row of every screen beneath the window title.
            .background(palette.background.ignoresSafeArea())
        }
        .alert("Something went wrong",
               isPresented: Binding(
                   get: { model.error != nil },
                   set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
        // Shown once, after the one-shot move out of ~/.claude/fluent-data.
        // An alert rather than the working overlay: that overlay is cleared only
        // by the generation and grading paths, so a launch-time message there
        // would pin a spinner on screen for the rest of the session.
        .alert("Your learning data moved",
               isPresented: Binding(
                   get: { model.migrationNotice != nil },
                   set: { if !$0 { model.migrationNotice = nil } })) {
            Button("OK") { model.migrationNotice = nil }
        } message: {
            Text(model.migrationNotice ?? "")
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
        if model.activeProfile == nil {
            WelcomeView()
        } else {
            screenContent
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch model.screen {
        case .home:
            HomeView()
        case let .lesson(id):
            if let record = model.record(id: id) {
                LessonPlayerView(id: record.id)
            } else {
                missing
            }
        case .archive:
            ArchiveView()
        case .lists:
            ListsView()
        case .images:
            ImagesView()
        case .scratch:
            ScratchPadView()
        case .progress:
            ProgressDashboard()
        case .script:
            ScriptDrillView()
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
