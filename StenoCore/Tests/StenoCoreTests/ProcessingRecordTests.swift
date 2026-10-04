import Foundation
import Testing
import StenoCore

@Suite("Coda di Elaborazione")
struct ProcessingRecordTests {
    let start = Date(timeIntervalSince1970: 1_791_117_000)

    func record(_ status: ProcessingRecord.Status, minutesAfterStart minutes: Double = 0) -> ProcessingRecord {
        ProcessingRecord(
            stenoID: UUID(), startedAt: start.addingTimeInterval(minutes * 60),
            status: status, templateName: "Generico", summaryProfile: nil, noteURL: nil
        )
    }

    @Test("al riavvio si riprendono, dalla più vecchia, le Riunioni in coda, in corso o interrotte durante la registrazione")
    func resumeAfterRestart() {
        let completed = record(.completed, minutesAfterStart: 0)
        let failed = record(.failed(reason: "401"), minutesAfterStart: 10)
        let processing = record(.processing, minutesAfterStart: 30)
        let queued = record(.queued, minutesAfterStart: 20)
        let interrupted = record(.recording, minutesAfterStart: 40)

        let plan = ProcessingRecord.afterRestart([interrupted, completed, processing, failed, queued])

        #expect(plan.toProcess.map(\.stenoID) == [queued.stenoID, processing.stenoID, interrupted.stenoID])
        #expect(plan.toSave.isEmpty)
    }

    @Test("lo stato salvato su disco si rilegge identico, compreso il motivo di un fallimento")
    func persistence() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var saved = record(.failed(reason: "Il provider ha risposto con l'errore 401"))
        saved.summaryProfile = ProviderProfile(name: "Mistral UE", baseURL: "https://api.mistral.ai/v1", model: "m", maxContextTokens: 32_000)
        saved.noteURL = URL(filePath: "/Vault/Meetings/2026-10-04 1430 - Riunione.md")

        try saved.save(in: directory)

        #expect(try ProcessingRecord.load(from: directory) == saved)
    }

    @Test("una Registrazione interrotta da un crash si ricostruisce dagli elenchi dei segmenti salvati")
    func recoveredRecording() {
        let id = UUID()
        let end = start.addingTimeInterval(612)
        let others = [Segment(track: .others, index: 1, start: 300.1), Segment(track: .others, index: 0, start: 0.1)]
        let me = [Segment(track: .me, index: 0, start: 0.2), Segment(track: .me, index: 1, start: 300.2)]

        let recording = Recording.recovered(stenoID: id, startedAt: start, segments: others + me, lastWrite: end)

        #expect(recording.meetingID == id)
        #expect(recording.endedAt == end)
        #expect(recording.segments.map(\.fileName) == ["io-000.m4a", "io-001.m4a", "altri-000.m4a", "altri-001.m4a"])
    }

    @Test("al riavvio una Rigenerazione interrotta non diventa un'Elaborazione completa: la Riunione torna completata")
    func interruptedRegeneration() {
        let regenerating = record(.regenerating, minutesAfterStart: 5)
        let queued = record(.queued, minutesAfterStart: 10)

        let plan = ProcessingRecord.afterRestart([regenerating, queued])

        #expect(plan.toProcess.map(\.stenoID) == [queued.stenoID])
        #expect(plan.toSave.map(\.stenoID) == [regenerating.stenoID])
        #expect(plan.toSave.first?.status == .completed)
    }

    @Test("Riprova e Rigenera sono possibili solo per Riunioni completate o fallite", arguments: [
        (ProcessingRecord.Status.completed, true),
        (.failed(reason: "401"), true),
        (.recording, false),
        (.queued, false),
        (.processing, false),
        (.regenerating, false),
    ])
    func retryAllowed(status: ProcessingRecord.Status, allowed: Bool) {
        var retried = record(status)
        var regenerated = record(status)

        #expect(status.canRetry == allowed)
        #expect(((try? retried.queueForRetry()) != nil) == allowed)
        #expect(((try? regenerated.beginRegeneration()) != nil) == allowed)
        if allowed {
            #expect(retried.status == .queued)
            #expect(regenerated.status == .regenerating)
        } else {
            #expect(retried.status == status)
        }
    }
}
