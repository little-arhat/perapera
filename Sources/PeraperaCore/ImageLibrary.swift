import Foundation

/// A photograph the app generated, kept for reuse.
///
/// Each one cost about $0.07 to make and verify. Using it once inside the
/// lesson that produced it is the waste — the picture does not go stale, and a
/// sign you read a month ago is exactly what spaced repetition is for.
public struct LibraryImage: Equatable, Sendable, Identifiable {
    /// Unique across the library: lesson id plus exercise id.
    public let id: String
    public let lessonId: String
    public let exerciseId: String
    public let fileName: String
    /// The text visible in the picture, verified at generation time.
    public let targets: [String]
    /// Readings the learner may type. What grading compares against.
    public let accepted: [String]
    public let question: String?
    public let capturedAt: Date
    /// The lesson it came from, for provenance in the gallery.
    public let lessonTitle: String

    public init(
        lessonId: String, exerciseId: String, fileName: String,
        targets: [String], accepted: [String], question: String?,
        capturedAt: Date, lessonTitle: String
    ) {
        self.id = "\(lessonId)/\(exerciseId)"
        self.lessonId = lessonId
        self.exerciseId = exerciseId
        self.fileName = fileName
        self.targets = targets
        self.accepted = accepted
        self.question = question
        self.capturedAt = capturedAt
        self.lessonTitle = lessonTitle
    }
}

public enum ImageLibrary {
    /// Every verified photograph across every lesson, newest first.
    ///
    /// Built by walking the records rather than kept as its own index: the
    /// records are the source of truth, and a parallel index would be a second
    /// thing to keep in step for no gain at this size.
    public static func collect(
        from records: [LessonRecord], standalone: [StandalonePicture] = []
    ) -> [LibraryImage] {
        var images: [LibraryImage] = []
        for record in records {
            for exercise in record.lesson.exercises {
                guard
                    let fileName = record.images[exercise.id],
                    case let .recognition(spec, accepted) = exercise.content
                else { continue }
                images.append(
                    LibraryImage(
                        lessonId: record.id,
                        exerciseId: exercise.id,
                        fileName: fileName,
                        targets: spec.targets,
                        accepted: accepted,
                        question: spec.question,
                        capturedAt: record.lesson.generatedAt,
                        lessonTitle: record.displayTitle))
            }
        }
        // Pictures made outside a lesson live under a reserved lesson id, so
        // the rest of the app — file paths, review, the contact sheet — needs
        // no special case for them.
        for picture in standalone {
            images.append(
                LibraryImage(
                    lessonId: standaloneFolder,
                    exerciseId: picture.id,
                    fileName: picture.fileName,
                    targets: picture.targets,
                    accepted: picture.accepted,
                    question: picture.question,
                    capturedAt: picture.createdAt,
                    lessonTitle: picture.sourceLabel))
        }
        return images.sorted { $0.capturedAt > $1.capturedAt }
    }

    /// Where on-demand pictures are stored. Not a lesson id any lesson can
    /// have: lesson ids are timestamped and always start "lesson-".
    public static let standaloneFolder = "on-demand"

    /// Picks the next image to review, avoiding the one just shown.
    ///
    /// Not SM-2: these are not scheduled items, and pretending otherwise would
    /// put a second scheduler beside Fluent's. Plain random, minus the last
    /// one, which is what "show me another" means with a small library.
    public static func next(
        from images: [LibraryImage], excluding lastShown: String?
    ) -> LibraryImage? {
        guard !images.isEmpty else { return nil }
        let candidates = images.count > 1
            ? images.filter { $0.id != lastShown }
            : images
        return candidates.randomElement()
    }
}
