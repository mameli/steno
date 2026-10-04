import Foundation
import Testing
import StenoCore

@Suite("Meeting state")
struct MeetingStateMachineTests {
    let start = Date(timeIntervalSince1970: 1_791_120_600)

    @Test("starting a Meeting from idle puts it in progress")
    func startFromIdle() throws {
        var machine = MeetingStateMachine()
        #expect(machine.state == .idle)

        try machine.start(at: start)

        #expect(machine.state == .inProgress(startedAt: start))
    }

    @Test("a Meeting cannot start while another one is in progress")
    func cannotStartTwice() throws {
        var machine = MeetingStateMachine()
        try machine.start(at: start)

        #expect(throws: MeetingStateError.alreadyInProgress) {
            try machine.start(at: start.addingTimeInterval(60))
        }
        #expect(machine.state == .inProgress(startedAt: start))
    }

    @Test("stopping a Meeting returns its start and end and goes back to idle")
    func stopReturnsInterval() throws {
        var machine = MeetingStateMachine()
        try machine.start(at: start)
        let end = start.addingTimeInterval(47 * 60)

        let interval = try machine.stop(at: end)

        #expect(interval == DateInterval(start: start, end: end))
        #expect(machine.state == .idle)
    }

    @Test("stopping when no Meeting is in progress is an error")
    func cannotStopWhenIdle() {
        var machine = MeetingStateMachine()

        #expect(throws: MeetingStateError.notInProgress) {
            try machine.stop(at: start)
        }
        #expect(machine.state == .idle)
    }
}
