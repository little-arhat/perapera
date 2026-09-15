import Testing
@testable import PeraperaApp
@testable import PeraperaCore

// The prompt an image model gets. The scene varies; what every picture needs
// does not, and lives here so a teacher's scene and an on-demand one get it
// alike.

@MainActor
@Test func everyImagePromptCarriesTheTextAndMakesItTheSubject() {
    let spec = Exercise.ImageSpec(
        scene: "A navy noren. The text is written vertically, in gyosho.",
        targets: ["呉服", "ごふく"], question: nil)
    let prompt = ImagePipeline.instruction(for: spec)
    #expect(prompt.hasPrefix(spec.scene))
    #expect(prompt.contains("- 呉服"))
    #expect(prompt.contains("- ごふく"))
    #expect(prompt.contains("fills most of the frame"))
    #expect(prompt.contains("no real company names"))
}
