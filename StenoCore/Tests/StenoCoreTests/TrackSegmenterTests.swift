import Foundation
import Testing
import StenoCore

@Suite("Suddivisione di una Traccia in segmenti")
struct TrackSegmenterTests {
    @Test("il primo buffer va nel segmento 0, che inizia quando inizia la Traccia")
    func firstBuffer() {
        var segmenter = TrackSegmenter(track: .me, sampleRate: 16_000, trackStart: 0.25)

        let segment = segmenter.place(frameCount: 1_600)

        #expect(segment.index == 0)
        #expect(segment.fileName == "io-000.m4a")
        #expect(segment.start == 0.25)
    }

    @Test("dopo 5 minuti di audio il buffer successivo apre un nuovo segmento")
    func rotatesAfterSegmentDuration() {
        var segmenter = TrackSegmenter(track: .others, sampleRate: 16_000, trackStart: 0.25)
        for _ in 0..<300 {
            #expect(segmenter.place(frameCount: 16_000).index == 0)
        }

        let segment = segmenter.place(frameCount: 16_000)

        #expect(segment.index == 1)
        #expect(segment.fileName == "altri-001.m4a")
        #expect(segment.start == 300.25)
    }

    @Test("una Traccia di 12 minuti fermata a metà segmento produce 3 segmenti, l'ultimo incompleto")
    func stopMidSegment() {
        var segmenter = TrackSegmenter(track: .me, sampleRate: 16_000, trackStart: 0)
        for _ in 0..<720 {
            _ = segmenter.place(frameCount: 16_000)
        }

        #expect(segmenter.segments.map(\.fileName) == ["io-000.m4a", "io-001.m4a", "io-002.m4a"])
        #expect(segmenter.segments.map(\.start) == [0, 300, 600])
    }

    @Test("una Traccia senza audio non ha segmenti")
    func emptyTrack() {
        let segmenter = TrackSegmenter(track: .others, sampleRate: 48_000, trackStart: 0)

        #expect(segmenter.segments.isEmpty)
    }
}
