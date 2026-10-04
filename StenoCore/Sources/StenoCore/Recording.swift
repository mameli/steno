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
}
