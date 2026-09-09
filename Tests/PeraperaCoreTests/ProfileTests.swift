import Foundation
import Testing
@testable import PeraperaCore

// A profile id is a directory name a person reads in Finder and a path the
// terminal has to quote. It must be stable, obvious, and free of anything a
// shell or a filesystem treats specially.

@Test func slugIsNameAndLanguage() {
    #expect(ProfileSlug.make(LearnerIdentity(name: "Roma", targetLanguage: "Japanese"))
            == "roma-japanese")
}

@Test func slugFlattensSpacesPunctuationAndCase() {
    #expect(ProfileSlug.make(LearnerIdentity(name: "Ana María",
                                             targetLanguage: "Brazilian Portuguese"))
            == "ana-maria-brazilian-portuguese")
}

@Test func slugSurvivesANameWithNothingLatinInIt() {
    let slug = ProfileSlug.make(LearnerIdentity(name: "ローマ", targetLanguage: "日本語"))
    #expect(!slug.isEmpty)
    #expect(!slug.contains("/"))
    #expect(!slug.contains(" "))
}

@Test func slugIsStableAcrossRuns() {
    // The fallback must not be String.hashValue: Swift seeds it per process, so
    // a learner with no ASCII in their name would get a fresh directory every
    // launch and lose their history to an orphan each time. Asserting the literal
    // value is what catches that; two calls in one process would agree either way.
    #expect(ProfileSlug.make(LearnerIdentity(name: "ローマ", targetLanguage: "日本語"))
            == "profile-3acccf77d146")
}

@Test func uniqueSuffixesOnlyOnCollision() {
    let identity = LearnerIdentity(name: "Roma", targetLanguage: "Japanese")
    #expect(ProfileSlug.unique(identity, taken: []) == "roma-japanese")
    #expect(ProfileSlug.unique(identity, taken: ["roma-japanese"]) == "roma-japanese-2")
    #expect(ProfileSlug.unique(identity, taken: ["roma-japanese", "roma-japanese-2"])
            == "roma-japanese-3")
}

@Test func migrationRunsOnceAndOnlyWithSomethingToMove() {
    let roma = LearnerIdentity(name: "Roma", targetLanguage: "Japanese")
    #expect(MigrationDecision.decide(legacyHasProfile: true, existingSlugs: [], identity: roma)
            == .migrate(slug: "roma-japanese"))
    #expect(MigrationDecision.decide(legacyHasProfile: true,
                                     existingSlugs: ["roma-japanese"], identity: roma)
            == .skip("already migrated"))
    #expect(MigrationDecision.decide(legacyHasProfile: false, existingSlugs: [], identity: nil)
            == .skip("nothing to migrate"))
    // An unreadable legacy profile is a case for a person, not for a guess about
    // whose data it is.
    #expect(MigrationDecision.decide(legacyHasProfile: true, existingSlugs: [], identity: nil)
            == .skip("legacy profile unreadable"))
}
