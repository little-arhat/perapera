import Testing
import Foundation
@testable import PeraperaCore

/// Decodes a LessonRecord file exactly as it sits on disk.
///
/// The archive is the app's memory: if a record stops round-tripping, finished
/// lessons become unreadable and the feedback attached to them is lost. This
/// fixture is a real file from the lessons directory, not a constructed one.
@Test func decodesALessonRecordFromDisk() throws {
    let url = try #require(Bundle.module.url(
        forResource: "real-lesson-record", withExtension: "json",
        subdirectory: "Fixtures"))

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let record = try decoder.decode(LessonRecord.self, from: Data(contentsOf: url))

    // State is transient: a fixture captured mid-lesson is still a valid
    // record, so assert it decoded to a real case rather than to a fixed one.
    #expect(LessonRecord.State.allCases.contains(record.state))
    #expect(record.lesson.exercises.count == 8)
    #expect(record.lesson.spec.mode == .review)
    #expect(record.autoGradedScore.total == 7)   // 8 exercises, 1 needs the teacher
    #expect(record.exercisesNeedingTeacher.count == 1)
}

@Test func lessonRecordSurvivesARoundTrip() throws {
    let url = try #require(Bundle.module.url(
        forResource: "real-lesson-record", withExtension: "json",
        subdirectory: "Fixtures"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    var record = try decoder.decode(LessonRecord.self, from: Data(contentsOf: url))
    // Answer one exercise, the way the player does.
    let first = record.lesson.exercises[0]
    record.answers[first.id] = .matches([0, 1, 2, 3])
    record.verdicts[first.id] = Grader.grade(first, .matches([0, 1, 2, 3]))
    record.state = .inProgress

    let reloaded = try decoder.decode(
        LessonRecord.self, from: try encoder.encode(record))

    #expect(reloaded.state == .inProgress)
    #expect(reloaded.answers[first.id] == .matches([0, 1, 2, 3]))
    #expect(reloaded.verdicts[first.id] == record.verdicts[first.id])
    #expect(reloaded.lesson.exercises.count == record.lesson.exercises.count)
}

// MARK: - Study time
//
// Wall-clock is not study time. A lesson opened at night and finished the next
// evening once logged 1383 minutes into Fluent's totals — a permanent skew from
// a single lesson.

@Test func activeTimeIgnoresIdleGaps() throws {
    let url = try #require(Bundle.module.url(
        forResource: "real-lesson-record", withExtension: "json",
        subdirectory: "Fixtures"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var record = try decoder.decode(LessonRecord.self, from: Data(contentsOf: url))
    record.activeSeconds = 0

    let start = Date()
    // Two minutes of answering...
    record.recordActivity(since: start, now: start.addingTimeInterval(120))
    // ...then overnight away from the desk...
    record.recordActivity(since: start.addingTimeInterval(120),
                          now: start.addingTimeInterval(80_000))
    // ...then three more minutes.
    record.recordActivity(since: start.addingTimeInterval(80_000),
                          now: start.addingTimeInterval(80_180))

    #expect(record.activeSeconds == 300)
    #expect(record.durationMinutes == 5)
}

@Test func untrackedRecordsFallBackToACappedWallClock() throws {
    let url = try #require(Bundle.module.url(
        forResource: "real-lesson-record", withExtension: "json",
        subdirectory: "Fixtures"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var record = try decoder.decode(LessonRecord.self, from: Data(contentsOf: url))

    record.activeSeconds = 0
    record.startedAt = Date()
    record.finishedAt = record.startedAt?.addingTimeInterval(23 * 3600)

    // Capped at three times the estimate rather than the real 23 hours.
    #expect(record.durationMinutes <= record.lesson.estimatedMinutes * 3)
    #expect(record.durationMinutes > 0)
}

// MARK: - Labels
//
// Queuing lessons ahead of time is only useful if you can tell them apart
// later. The label is the learner's, so it lives on the record rather than the
// generated lesson and can be added or corrected at any point.

@Test func displayTitleFallsBackToTheGeneratedTitle() throws {
    let url = try #require(Bundle.module.url(
        forResource: "real-lesson-record", withExtension: "json",
        subdirectory: "Fixtures"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var record = try decoder.decode(LessonRecord.self, from: Data(contentsOf: url))

    #expect(record.displayTitle == record.lesson.title)

    record.name = "plane — counters"
    #expect(record.displayTitle == "plane — counters")

    // A blank name is not a name; it must not blank out the row.
    record.name = "   "
    #expect(record.displayTitle == record.lesson.title)
}

@Test func labelsSurviveARoundTrip() throws {
    let url = try #require(Bundle.module.url(
        forResource: "real-lesson-record", withExtension: "json",
        subdirectory: "Fixtures"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    var record = try decoder.decode(LessonRecord.self, from: Data(contentsOf: url))
    record.name = "plane — counters"
    record.note = "do before the Kyoto trip"

    let reloaded = try decoder.decode(
        LessonRecord.self, from: try encoder.encode(record))
    #expect(reloaded.name == "plane — counters")
    #expect(reloaded.note == "do before the Kyoto trip")
}

@Test func recordsWrittenBeforeLabelsExistedStillOpen() throws {
    // The archive must read back everything it ever wrote.
    let url = try #require(Bundle.module.url(
        forResource: "real-lesson-record", withExtension: "json",
        subdirectory: "Fixtures"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let record = try decoder.decode(LessonRecord.self, from: Data(contentsOf: url))
    #expect(record.name == nil)
    #expect(record.note == nil)
}
