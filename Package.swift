// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Perapera",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure: models, grading, kana, payload building. No SwiftUI, no
        // subprocesses -- everything here is testable without a UI or a network.
        .target(name: "PeraperaCore"),

        // The app shell: SwiftUI views plus the two effectful edges
        // (ClaudeClient, FluentStore) that talk to `claude` and `update-db.py`.
        .executableTarget(
            name: "PeraperaApp",
            dependencies: ["PeraperaCore"],
            resources: [
                // Prompts and schemas are plain files on purpose: the wording of
                // a prompt is content, not code, and should be diffable and
                // editable without a rebuild-shaped mental model.
                .copy("Resources/Prompts"),
                .copy("Resources/Schemas"),
                .copy("Resources/teacher-context.json"),
            ]
        ),

        .testTarget(
            name: "PeraperaAppTests",
            dependencies: ["PeraperaApp", "PeraperaCore"]
        ),

        .testTarget(
            name: "PeraperaCoreTests",
            dependencies: ["PeraperaCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
