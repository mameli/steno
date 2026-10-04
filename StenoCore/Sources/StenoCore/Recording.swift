import Foundation

/// The audio of a Meeting: when it started and the Segments each Track is saved in.
public struct Recording: Codable, Equatable, Sendable {
    public let meetingID: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let segments: [Segment]

    public init(meetingID: UUID, startedAt: Date, endedAt: Date, segments: [Segment]) {
        self.meetingID = meetingID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.segments = segments
    }

    /// The manifest in the Recording folder.
    public static let fileName = "recording.json"

    /// Segment sample rate: mono 16 kHz, what Whisper expects.
    public static let sampleRate: Double = 16_000

    /// Reads the manifest of a Recording folder.
    public static func load(fromFolder folder: URL) throws -> Recording {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Recording.self, from: Data(contentsOf: folder.appending(path: fileName)))
    }

    public func save(inFolder folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: folder.appending(path: Self.fileName), options: .atomic)
    }

    /// A Recording interrupted by a crash, rebuilt from the Segment lists each Track saves
    /// whenever a Segment opens. The end is the last write to disk.
    public static func recovered(stenoID: UUID, startedAt: Date, segments: [Segment], lastWrite: Date) -> Recording {
        let ordered = Track.allCases.flatMap { track in
            segments.filter { $0.track == track }.sorted { $0.index < $1.index }
        }
        return Recording(meetingID: stenoID, startedAt: startedAt, endedAt: lastWrite, segments: ordered)
    }
}
