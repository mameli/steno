import Testing
import TakkuCore

@Suite("Call start and end")
struct CallWatchTests {
    /// Feeds the watch every 3 seconds from `from` to `to` and returns what it suggested, with when.
    func run(
        _ watch: inout CallWatch, apps: Set<String>, recording: Bool, from: Double, to: Double
    ) -> [(Double, CallWatch.Suggestion)] {
        stride(from: from, through: to, by: 3).compactMap { now in
            watch.update(appsUsingInput: apps, isRecording: recording, now: now).map { (now, $0) }
        }
    }

    @Test("an app on the microphone for 15 seconds suggests a start, once per stretch of use")
    func start() {
        var watch = CallWatch()
        let suggestions = run(&watch, apps: ["Zoom"], recording: false, from: 0, to: 60)

        #expect(suggestions.map(\.1) == [.start(app: "Zoom")])
        #expect(suggestions.first?.0 == 15)
    }

    @Test("a short dictation suggests nothing; a new stretch of use suggests again")
    func shortUse() {
        var watch = CallWatch()
        #expect(run(&watch, apps: ["Handy"], recording: false, from: 0, to: 12).isEmpty)
        #expect(run(&watch, apps: [], recording: false, from: 15, to: 30).isEmpty)
        #expect(run(&watch, apps: ["Zoom"], recording: false, from: 33, to: 48).map(\.1) == [.start(app: "Zoom")])
        _ = run(&watch, apps: [], recording: false, from: 51, to: 51)
        #expect(run(&watch, apps: ["Zoom"], recording: false, from: 54, to: 69).map(\.1) == [.start(app: "Zoom")])
    }

    @Test("when the call app lets the microphone go for 30 seconds while recording, a stop is suggested once")
    func stop() {
        var watch = CallWatch()
        _ = run(&watch, apps: ["Teams"], recording: true, from: 0, to: 300)
        let suggestions = run(&watch, apps: [], recording: true, from: 303, to: 600)

        #expect(suggestions.map(\.1) == [.stop])
        #expect(suggestions.first?.0 == 330)
    }

    @Test("a Meeting without any call app on the microphone gets no stop suggestion")
    func noCallNoStop() {
        var watch = CallWatch()
        #expect(run(&watch, apps: [], recording: true, from: 0, to: 600).isEmpty)
    }

    @Test("a call taken back and released again suggests the stop again")
    func stopAgain() {
        var watch = CallWatch()
        _ = run(&watch, apps: ["Teams"], recording: true, from: 0, to: 30)
        #expect(run(&watch, apps: [], recording: true, from: 33, to: 90).map(\.1) == [.stop])
        _ = run(&watch, apps: ["Teams"], recording: true, from: 93, to: 120)
        #expect(run(&watch, apps: [], recording: true, from: 123, to: 200).map(\.1) == [.stop])
    }

    @Test("stopping by hand during a call does not suggest starting again for the same call")
    func stoppedDuringCall() {
        var watch = CallWatch()
        _ = run(&watch, apps: ["Meet"], recording: true, from: 0, to: 60)

        #expect(run(&watch, apps: ["Meet"], recording: false, from: 63, to: 200).isEmpty)
    }
}
