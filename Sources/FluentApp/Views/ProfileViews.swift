import AppKit
import SwiftUI
import FluentCore

/// Who the app is currently teaching.
///
/// Sits above the sidebar sections because it scopes every one of them: changing
/// it changes the archive, the pictures, the saved words and the schedule together.
struct ProfileSwitcher: View {
    @Environment(AppModel.self) private var model
    @State private var creating = false

    var body: some View {
        Menu {
            ForEach(model.profiles.list()) { profile in
                Button {
                    Task { await model.switchProfile(to: profile.id) }
                } label: {
                    Label("\(profile.identity.name) · \(profile.identity.targetLanguage)",
                          systemImage: profile.id == model.activeProfile?.id
                              ? "checkmark" : "person")
                }
            }
            Divider()
            Button("New profile…") { creating = true }
            // No Delete. Removing a profile removes a learner's whole history;
            // Finder is the right place for a decision that can be reconsidered.
            Button("Reveal in Finder") {
                if let directory = model.dataDirectory {
                    NSWorkspace.shared.activateFileViewerSelecting([directory])
                }
            }
            .disabled(model.dataDirectory == nil)
        } label: {
            Label(model.activeProfile.map {
                "\($0.identity.name) · \($0.identity.targetLanguage)"
            } ?? "No profile", systemImage: "person.crop.circle")
        }
        .menuStyle(.borderlessButton)
        .sheet(isPresented: $creating) { NewProfileSheet() }
    }
}

/// What a fresh install shows. Without it the app opens on an empty Practice
/// screen and an unexplained database error.
struct WelcomeView: View {
    @State private var creating = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Perapera").font(.largeTitle)
            Text("Create a profile to begin. One profile holds one learner and one "
                 + "target language, with its own schedule, archive and vocabulary.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .foregroundStyle(.secondary)
            Button("Create a profile…") { creating = true }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $creating) { NewProfileSheet() }
    }
}

struct NewProfileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var language = "Japanese"
    // Asked for, not defaulted: the generation prompt substitutes both, and a
    // wrong native language quietly changes how every explanation is written.
    @State private var nativeLanguage = ""
    @State private var explanationLanguage = "English"
    @State private var currentLevel = "A1"
    @State private var targetLevel = "B2"
    @State private var dailyMinutes = 30
    @State private var motivation = "personal"
    @State private var busy = false
    @State private var failure: String?

    private let levels = ["A1", "A2", "B1", "B2", "C1", "C2"]
    private let goals = ["travel", "work", "exam", "living_abroad", "personal", "family"]

    private var incomplete: Bool {
        [name, language, nativeLanguage]
            .contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Target language", text: $language)
            TextField("Native language", text: $nativeLanguage)
            TextField("Explain things in", text: $explanationLanguage)
            Picker("Level now", selection: $currentLevel) {
                ForEach(levels, id: \.self, content: Text.init)
            }
            Picker("Level wanted", selection: $targetLevel) {
                ForEach(levels, id: \.self, content: Text.init)
            }
            Picker("Goal", selection: $motivation) {
                ForEach(goals, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")) }
            }
            Stepper("Minutes a day: \(dailyMinutes)", value: $dailyMinutes, in: 5...180, step: 5)

            Text("Not sure of your level? Fluent's `/fluent-setup` runs a placement "
                 + "assessment and writes the same profile.")
                .font(.caption).foregroundStyle(.secondary)

            if let failure {
                Text(failure).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(incomplete || busy)
            }
        }
        .padding()
        .frame(width: 400)
        .disabled(busy)
    }

    private func create() {
        busy = true
        failure = nil
        let trimmed = { (s: String) in s.trimmingCharacters(in: .whitespaces) }
        Task {
            do {
                let profile = try await model.profiles.create(
                    identity: LearnerIdentity(name: trimmed(name),
                                              targetLanguage: trimmed(language)),
                    currentLevel: currentLevel, targetLevel: targetLevel,
                    nativeLanguage: trimmed(nativeLanguage),
                    explanationLanguage: trimmed(explanationLanguage),
                    motivation: motivation, learningStyle: "balanced",
                    timeline: "1_year", dailyMinutes: dailyMinutes,
                    otherLanguages: [], fluentRoot: model.fluentRoot)
                dismiss()
                await model.switchProfile(to: profile.id)
            } catch {
                failure = error.localizedDescription
            }
            busy = false
        }
    }
}
