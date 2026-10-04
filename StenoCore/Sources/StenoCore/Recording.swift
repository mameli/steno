import Foundation

/// L'audio di una Riunione: quando è iniziata e i segmenti in cui è salvata ogni Traccia.
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

    /// Frequenza di campionamento dei segmenti: mono 16 kHz, quella che si aspetta Whisper.
    public static let sampleRate: Double = 16_000

    public static func load(from url: URL) throws -> Recording {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Recording.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
