import Foundation
import Testing
import StenoCore

@Suite("Stato della Riunione")
struct MeetingStateMachineTests {
    let start = Date(timeIntervalSince1970: 1_791_120_600)

    @Test("avviare una Riunione da inattivo la mette in corso")
    func startFromIdle() throws {
        var machine = MeetingStateMachine()
        #expect(machine.state == .idle)

        try machine.start(at: start)

        #expect(machine.state == .inProgress(startedAt: start))
    }

    @Test("non si può avviare una Riunione mentre un'altra è in corso")
    func cannotStartTwice() throws {
        var machine = MeetingStateMachine()
        try machine.start(at: start)

        #expect(throws: MeetingStateError.alreadyInProgress) {
            try machine.start(at: start.addingTimeInterval(60))
        }
        #expect(machine.state == .inProgress(startedAt: start))
    }

    @Test("fermare una Riunione restituisce inizio e fine e torna inattivo")
    func stopReturnsInterval() throws {
        var machine = MeetingStateMachine()
        try machine.start(at: start)
        let end = start.addingTimeInterval(47 * 60)

        let interval = try machine.stop(at: end)

        #expect(interval == DateInterval(start: start, end: end))
        #expect(machine.state == .idle)
    }

    @Test("fermare quando non c'è una Riunione in corso è un errore")
    func cannotStopWhenIdle() {
        var machine = MeetingStateMachine()

        #expect(throws: MeetingStateError.notInProgress) {
            try machine.stop(at: start)
        }
        #expect(machine.state == .idle)
    }
}
