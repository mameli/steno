import Foundation

/// The Marks of a Meeting, in seconds from its start, saved in the Recording folder as soon as
/// they are made so they survive a crash.
public enum Marks {
    public static let fileName = "marks.json"

    /// The Marks saved in a Recording folder; none if the file is missing or unreadable.
    public static func load(fromFolder folder: URL) -> [TimeInterval] {
        (try? JSONDecoder().decode([TimeInterval].self, from: Data(contentsOf: folder.appending(path: fileName)))) ?? []
    }

    public static func save(_ marks: [TimeInterval], inFolder folder: URL) throws {
        try JSONEncoder().encode(marks).write(to: folder.appending(path: fileName), options: .atomic)
    }
}
