import Foundation
import Testing
import StenoCore

@Suite("Conservazione delle Registrazioni")
struct RetentionTests {
    let now = Date(timeIntervalSince1970: 1_791_117_000)
    let day: TimeInterval = 86_400

    func item(_ daysAgo: Double, _ status: ProcessingRecord.Status?) -> Retention.Item {
        Retention.Item(stenoID: UUID(), startedAt: now.addingTimeInterval(-daysAgo * day), status: status)
    }

    @Test("dopo 7 giorni si cancellano le Registrazioni elaborate o fallite, mai quelle ancora da elaborare")
    func expired() {
        let oldCompleted = item(8, .completed)
        let oldFailed = item(10, .failed(reason: "401"))
        let oldWithoutRecord = item(30, nil)
        let recentCompleted = item(6.9, .completed)
        let oldQueued = item(9, .queued)
        let oldProcessing = item(9, .processing)
        let oldRecording = item(9, .recording)
        let oldRegenerating = item(9, .regenerating)

        let expired = Retention.expired(
            [oldCompleted, oldFailed, oldWithoutRecord, recentCompleted, oldQueued, oldProcessing, oldRecording, oldRegenerating],
            now: now
        )

        #expect(Set(expired) == [oldCompleted.stenoID, oldFailed.stenoID, oldWithoutRecord.stenoID])
    }

    @Test("i giorni di conservazione si possono cambiare")
    func customDays() {
        let twoDaysOld = item(2, .completed)

        #expect(Retention.expired([twoDaysOld], now: now, days: 1) == [twoDaysOld.stenoID])
        #expect(Retention.expired([twoDaysOld], now: now, days: 3).isEmpty)
    }
}
