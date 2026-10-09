import Testing
import TakkuCore

@Suite("Silent Track")
struct TrackSilenceTests {
    @Test("a Track silent for less than 2 minutes is a pause, not a warning")
    func shortPause() {
        #expect(TrackSilence.silentMinutes(lastSound: 100, now: 219) == nil)
        #expect(TrackSilence.silentMinutes(lastSound: nil, now: 119) == nil)
    }

    @Test("after 2 minutes without sound the warning counts whole minutes, from the start if there was never any")
    func longSilence() {
        #expect(TrackSilence.silentMinutes(lastSound: 100, now: 220) == 2)
        #expect(TrackSilence.silentMinutes(lastSound: 100, now: 400) == 5)
        #expect(TrackSilence.silentMinutes(lastSound: nil, now: 130) == 2)
    }

    @Test("the notification is only for a Track that has had no sound since the start")
    func neverHeard() {
        #expect(TrackSilence.neverHeard(lastSound: nil, now: 120))
        #expect(!TrackSilence.neverHeard(lastSound: nil, now: 60))
        #expect(!TrackSilence.neverHeard(lastSound: 3, now: 600))
    }
}
