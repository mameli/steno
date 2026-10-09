import Foundation
import Testing
import TakkuCore

@Suite("Splitting a Track into Segments")
struct TrackSegmenterTests {
    @Test("the first buffer goes into Segment 0, which starts when the Track starts")
    func firstBuffer() {
        var segmenter = TrackSegmenter(track: .me, sampleRate: 16_000, trackStart: 0.25)

        let segment = segmenter.place(frameCount: 1_600)

        #expect(segment.index == 0)
        #expect(segment.fileName == "me-000.m4a")
        #expect(segment.start == 0.25)
    }

    @Test("after 5 minutes of audio the next buffer opens a new Segment")
    func rotatesAfterSegmentDuration() {
        var segmenter = TrackSegmenter(track: .others, sampleRate: 16_000, trackStart: 0.25)
        for _ in 0..<300 {
            #expect(segmenter.place(frameCount: 16_000).index == 0)
        }

        let segment = segmenter.place(frameCount: 16_000)

        #expect(segment.index == 1)
        #expect(segment.fileName == "others-001.m4a")
        #expect(segment.start == 300.25)
    }

    @Test("a 12-minute Track stopped mid-Segment produces 3 Segments, the last one incomplete")
    func stopMidSegment() {
        var segmenter = TrackSegmenter(track: .me, sampleRate: 16_000, trackStart: 0)
        for _ in 0..<720 {
            _ = segmenter.place(frameCount: 16_000)
        }

        #expect(segmenter.segments.map(\.fileName) == ["me-000.m4a", "me-001.m4a", "me-002.m4a"])
        #expect(segmenter.segments.map(\.start) == [0, 300, 600])
    }

    @Test("audio resuming 2 seconds late (microphone restarted) needs 2 seconds of silence first")
    func gapAfterRestart() {
        var segmenter = TrackSegmenter(track: .me, sampleRate: 16_000, trackStart: 0.25)
        _ = segmenter.place(frameCount: 16_000)

        // The first buffer covered 0.25-1.25 s: the next one should start at 1.25 s.
        #expect(segmenter.silenceFrames(beforeBufferAt: 3.25) == 32_000)
    }

    @Test("small delays from audio timing need no silence")
    func smallDelay() {
        var segmenter = TrackSegmenter(track: .me, sampleRate: 16_000, trackStart: 0)
        _ = segmenter.place(frameCount: 16_000)

        #expect(segmenter.silenceFrames(beforeBufferAt: 1.3) == 0)
        #expect(segmenter.silenceFrames(beforeBufferAt: 0.9) == 0)
    }

    @Test("before the first buffer there is nothing to fill")
    func noSilenceBeforeFirstBuffer() {
        let segmenter = TrackSegmenter(track: .me, sampleRate: 16_000, trackStart: 5)

        #expect(segmenter.silenceFrames(beforeBufferAt: 60) == 0)
    }

    @Test("a Track without audio has no Segments")
    func emptyTrack() {
        let segmenter = TrackSegmenter(track: .others, sampleRate: 48_000, trackStart: 0)

        #expect(segmenter.segments.isEmpty)
    }
}
