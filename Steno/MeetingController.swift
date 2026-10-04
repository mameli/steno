import AVFoundation
import AppKit
import Observation
import StenoCore
import os

private let logger = Logger(subsystem: "dev.mameli.steno", category: "riunione")

/// Avvio e stop della Riunione: permessi, registrazione, Nota della Riunione, scorciatoia globale.
/// Allo stop passa la Riunione a `MeetingProcessor`, che la elabora.
@MainActor
@Observable
final class MeetingController {
    private var machine = MeetingStateMachine()
    private let recorder = MeetingRecorder()
    private let transcriber = LocalTranscriber()
    let processor: MeetingProcessor
    private var currentStenoID: UUID?
    private var now = Date()
    private var isRequestingPermission = false
    private var ticker: Task<Void, Never>?
    private var hotKey: GlobalHotKey?
    /// Falso se un'altra app usa già ⌃⌥⌘R.
    var isHotKeyAvailable: Bool { hotKey?.isRegistered ?? false }
    private(set) var microphoneDenied = false
    private(set) var recordingError: String?
    private(set) var lastRecordingDirectory: URL?
    /// Template per la Riunione in corso o per la prossima; si può cambiare fino allo stop.
    var templateName = AppSettings.defaultTemplate {
        didSet {
            if let currentStenoID { processor.templateChanged(stenoID: currentStenoID, to: templateName) }
        }
    }

    init() {
        AppSettings.registerDefaults()
        processor = MeetingProcessor(transcriber: transcriber)
        templateName = AppSettings.defaultTemplate
        try? Vault.configured?.ensureDefaultTemplate()
        Notifications.shared.configure()
        hotKey = GlobalHotKey { [weak self] in self?.toggle() }
        processor.resumeAfterLaunch()
        startDailyCleanUp()
    }

    var isInProgress: Bool { machine.state != .idle }

    /// L'errore da mostrare nel menu: quello della registrazione o dell'ultima Elaborazione.
    var lastError: String? { recordingError ?? processor.lastError }

    /// Timer della Riunione in corso, `nil` se non ce n'è una.
    var elapsedText: String? {
        guard case .inProgress(let startedAt) = machine.state else { return nil }
        return elapsedLabel(max(0, now.timeIntervalSince(startedAt)))
    }

    /// ⌃⌥⌘R: avvia o ferma la Riunione da qualsiasi app.
    func toggle() {
        if isInProgress {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        // Il menu resta cliccabile mentre il popup del permesso è aperto.
        guard !isInProgress, !isRequestingPermission else { return }
        isRequestingPermission = true
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        isRequestingPermission = false

        microphoneDenied = !granted
        guard granted else { return }

        now = Date()
        let transcription = MeetingTranscription(transcriber: transcriber, language: AppSettings.forcedLanguage)
        let started: MeetingRecorder.Started
        do {
            started = try recorder.start(at: now, echoCancellation: AppSettings.echoCancellation) { segment, directory in
                Task { await transcription.segmentClosed(segment, in: directory) }
            }
        } catch {
            logger.error("Avvio della registrazione fallito: \(error, privacy: .public)")
            recordingError = error.localizedDescription
            return
        }
        do {
            try machine.start(at: now)
        } catch {
            assertionFailure("Avvio con una Riunione già in corso: \(error)")
            _ = try? recorder.stop(at: now)
            return
        }
        recordingError = nil
        currentStenoID = started.meetingID
        processor.meetingStarted(
            stenoID: started.meetingID,
            startedAt: now,
            templateName: templateName,
            summaryProfile: AppSettings.activeProviderProfile,
            noteURL: createMeetingNote(stenoID: started.meetingID, startedAt: now),
            transcription: transcription
        )
        startTicker()

        // Al primo uso scarica il modello: meglio farlo mentre la Riunione è in corso.
        Task { [transcriber] in
            do {
                try await transcriber.prepare()
            } catch {
                logger.error("Preparazione del modello fallita: \(error, privacy: .public)")
            }
        }
    }

    func stop() {
        let interval: DateInterval
        do {
            interval = try machine.stop(at: Date())
        } catch {
            assertionFailure("Stop senza una Riunione in corso: \(error)")
            return
        }
        ticker?.cancel()
        ticker = nil

        do {
            let stopped = try recorder.stop(at: interval.end)
            lastRecordingDirectory = stopped.directory
            if !stopped.errors.isEmpty {
                recordingError = "Registrazione incompleta: " + stopped.errors.joined(separator: "; ")
                logger.error("\(self.recordingError!, privacy: .public)")
            }
        } catch {
            logger.error("Chiusura della registrazione fallita: \(error, privacy: .public)")
            recordingError = error.localizedDescription
        }
        if let currentStenoID {
            processor.meetingStopped(stenoID: currentStenoID)
        }
        currentStenoID = nil
        templateName = AppSettings.defaultTemplate
    }

    /// Crea la Nota della Riunione nel Vault e la apre in Obsidian. Se non riesce la Riunione
    /// prosegue lo stesso: la nota verrà creata a fine Elaborazione.
    private func createMeetingNote(stenoID: UUID, startedAt: Date) -> URL? {
        guard let vault = Vault.configured else { return nil }
        do {
            let url = try vault.createMeetingNote(stenoID: stenoID, startedAt: startedAt)
            if AppSettings.openInObsidian {
                Task {
                    // Obsidian deve prima accorgersi del file nuovo.
                    try? await Task.sleep(for: .milliseconds(500))
                    Vault.openInObsidian(url)
                }
            }
            return url
        } catch {
            logger.error("Nota della Riunione non creata: \(error, privacy: .public)")
            recordingError = "\(error.localizedDescription) La nota verrà creata a fine Elaborazione."
            return nil
        }
    }

    /// L'audio scaduto si cancella all'avvio e poi una volta al giorno.
    private func startDailyCleanUp() {
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
                guard let self else { return }
                self.processor.cleanUpExpiredRecordings()
            }
        }
    }

    #if DEBUG
    /// Prove senza toccare il menu (l'esito finisce in `smoke-test.txt` accanto alla cartella dati, perché `log show` non è sempre leggibile):
    /// - `open Steno.app --args -smokeTestSeconds 20` registra per N secondi;
    /// - `open Steno.app --args -transcribeRecording <cartella>` rielabora una Registrazione della cartella dati;
    /// - `open Steno.app --args -regenerateMeeting <steno_id> -regenerateTemplate <nome>` rigenera il Riepilogo;
    /// - sempre insieme a `-vaultPath <cartella>`, `-testSummaryBaseURL <url>` e `-dataDirectory <cartella>`,
    ///   altrimenti la prova si rifiuta di partire; `-openInObsidian NO` non apre Obsidian.
    func runSmokeTestIfRequested() async {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        let isTest = ["smokeTestSeconds", "transcribeRecording", "regenerateMeeting"].contains { arguments[$0] != nil }
        let isIsolated = ["vaultPath", "testSummaryBaseURL", "dataDirectory"].allSatisfy { arguments[$0] != nil }
        guard !isTest || isIsolated else {
            // Una prova automatica senza isolamento scriverebbe nel Vault vero con il Provider vero.
            recordingError = "Prova automatica rifiutata: servono -vaultPath, -testSummaryBaseURL e -dataDirectory."
            writeSmokeTestOutcome(nil)
            return
        }
        if let id = UserDefaults.standard.string(forKey: "regenerateMeeting").flatMap(UUID.init(uuidString:)) {
            processor.regenerate(id, templateName: UserDefaults.standard.string(forKey: "regenerateTemplate"))
            await processor.waitUntilIdle()
            writeSmokeTestOutcome(processor.lastNoteURL)
            return
        }
        if let path = UserDefaults.standard.string(forKey: "transcribeRecording") {
            let url = await processor.reprocess(URL(filePath: path, directoryHint: .isDirectory))
            writeSmokeTestOutcome(url)
            return
        }

        let seconds = UserDefaults.standard.integer(forKey: "smokeTestSeconds")
        guard seconds > 0 else { return }
        await start()
        if isInProgress {
            try? await Task.sleep(for: .seconds(seconds))
            stop()
        }
        writeSmokeTestOutcome(lastRecordingDirectory)
    }

    private func writeSmokeTestOutcome(_ url: URL?) {
        let outcome = lastError.map { "errore: \($0)" } ?? "ok: \(url?.path ?? "-")"
        try? outcome.write(
            to: MeetingRecorder.meetingsDirectory.deletingLastPathComponent().appending(path: "smoke-test.txt"),
            atomically: true, encoding: .utf8
        )
    }
    #endif

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.now = Date()
            }
        }
    }
}
