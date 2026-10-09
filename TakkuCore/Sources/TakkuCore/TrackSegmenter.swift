import Foundation

/// A portion of a Track saved in its own file.
public struct Segment: Equatable, Codable, Sendable {
    public let track: Track
    public let index: Int
    /// Seconds from the start of the Meeting.
    public let start: TimeInterval

    public init(track: Track, index: Int, start: TimeInterval) {
        self.track = track
        self.index = index
        self.start = start
    }

    public var fileName: String {
        String(format: "%@-%03d.m4a", track.rawValue, index)
    }

    /// The transcription result of this Segment, saved next to the audio.
    public var transcriptionCacheFileName: String { fileName + ".json" }

    /// A Track's Segment list, updated every time a Segment opens (it survives a crash).
    public static func listFileName(for track: Track) -> String { "\(track.rawValue)-segments.json" }
}

/// Decides which Segment each buffer of a Track is written to.
///
/// Segments only change between buffers: a Segment may last a few milliseconds
/// longer than `segmentDuration`, but no buffer is ever split.
public struct TrackSegmenter: Sendable {
    public static let defaultSegmentDuration: TimeInterval = 300

    public let track: Track
    private let sampleRate: Double
    private let trackStart: TimeInterval
    private let framesPerSegment: Int
    /// The Segments opened so far, in order. The last one is being written.
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

    /// Below this, a late buffer is ordinary audio timing jitter (or clock drift), not a hole.
    private static let maxUnfilledGap: TimeInterval = 0.5

    /// Frames of silence to write before a buffer that starts at `time` (seconds from the start
    /// of the Meeting), so the Track stays aligned when the audio stopped for a while (e.g. the
    /// microphone restarting after a device change). Otherwise later Utterances would shift earlier.
    public func silenceFrames(beforeBufferAt time: TimeInterval) -> Int {
        guard !segments.isEmpty else { return 0 }
        let expected = trackStart + Double(framesBeforeCurrent + framesInCurrent) / sampleRate
        let gap = time - expected
        return gap > Self.maxUnfilledGap ? Int((gap * sampleRate).rounded()) : 0
    }

    /// Accounts for a buffer of `frameCount` frames and returns the Segment it must be written to.
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
