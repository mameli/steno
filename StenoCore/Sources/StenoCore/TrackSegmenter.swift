import Foundation

/// Un segmento di una Traccia salvato in un file a sé.
public struct Segment: Equatable, Codable, Sendable {
    public let track: Track
    public let index: Int
    /// Secondi dall'inizio della Riunione.
    public let start: TimeInterval

    public var fileName: String {
        String(format: "%@-%03d.m4a", track.rawValue, index)
    }
}

/// Decide in quale segmento va scritto ogni buffer di una Traccia.
///
/// Si cambia segmento solo tra un buffer e l'altro: un segmento può durare
/// qualche millisecondo più di `segmentDuration`, ma nessun buffer viene diviso.
public struct TrackSegmenter: Sendable {
    public static let defaultSegmentDuration: TimeInterval = 300

    public let track: Track
    private let sampleRate: Double
    private let trackStart: TimeInterval
    private let framesPerSegment: Int
    /// I segmenti aperti finora, in ordine. L'ultimo è quello in scrittura.
    public private(set) var segments: [Segment] = []
    private var framesBeforeCurrent = 0
    private var framesInCurrent = 0

    public init(
        track: Track,
        sampleRate: Double,
        trackStart: TimeInterval,
        segmentDuration: TimeInterval = defaultSegmentDuration
    ) {
        self.track = track
        self.sampleRate = sampleRate
        self.trackStart = trackStart
        self.framesPerSegment = Int(segmentDuration * sampleRate)
    }

    /// Registra un buffer di `frameCount` frame e restituisce il segmento in cui va scritto.
    public mutating func place(frameCount: Int) -> Segment {
        if let current = segments.last, framesInCurrent < framesPerSegment {
            framesInCurrent += frameCount
            return current
        }

        framesBeforeCurrent += framesInCurrent
        let segment = Segment(
            track: track,
            index: segments.count,
            start: trackStart + Double(framesBeforeCurrent) / sampleRate
        )
        segments.append(segment)
        framesInCurrent = frameCount
        return segment
    }
}
