import AVFoundation
import AppKit
import Observation
import StenoCore
import os

private let logger = Logger(subsystem: "dev.mameli.steno", category: "riunione")

/// Collega la macchina a stati della Riunione alla UI, ai permessi di sistema,
/// alla registrazione e alla trascrizione.
@MainActor
@Observable
final class MeetingController {
    /// Quello che serve per elaborare una Riunione dopo lo stop.
    private struct MeetingContext {
        let stenoID: UUID
        let startedAt: Date
        let noteURL: URL?
        let transcription: MeetingTranscription
    }

    private var machine = MeetingStateMachine()
    private let recorder = MeetingRecorder()
    private let transcriber = LocalTranscriber()
    private var current: MeetingContext?
    private var now = Date()
    private var isRequestingPermission = false
    private var ticker: Task<Void, Never>?
    private(set) var microphoneDenied = false
    private(set) var lastError: String?
    private(set) var lastRecordingDirectory: URL?
    private(set) var lastTranscriptURL: URL?
    private(set) var lastNoteURL: URL?
    private(set) var processingCount = 0

    init() {
        Settings.registerDefaults()
    }

    var isInProgress: Bool { machine.state != .idle }

    /// Timer della Riunione in corso, `nil` se non ce n'è una.
    var elapsedText: String? {
        guard case .inProgress(let startedAt) = machine.state else { return nil }
        return elapsedLabel(max(0, now.timeIntervalSince(startedAt)))
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
        let transcription = MeetingTranscription(transcriber: transcriber, language: Settings.forcedLanguage)
        let started: MeetingRecorder.Started
        do {
            started = try recorder.start(at: now, echoCancellation: Settings.echoCancellation) { segment, directory in
                Task { await transcription.segmentClosed(segment, in: directory) }
            }
        } catch {
            logger.error("Avvio della registrazione fallito: \(error, privacy: .public)")
            lastError = error.localizedDescription
            return
        }
        do {
            try machine.start(at: now)
        } catch {
            assertionFailure("Avvio con una Riunione già in corso: \(error)")
            _ = try? recorder.stop(at: now)
            return
        }
        lastError = nil
        current = MeetingContext(
            stenoID: started.meetingID,
            startedAt: now,
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

        let stopped: MeetingRecorder.Stopped
        do {
            stopped = try recorder.stop(at: interval.end)
        } catch {
            logger.error("Chiusura della registrazione fallita: \(error, privacy: .public)")
            lastError = error.localizedDescription
            return
        }
        lastRecordingDirectory = stopped.directory
        if !stopped.errors.isEmpty {
            lastError = "Registrazione incompleta: " + stopped.errors.joined(separator: "; ")
            logger.error("\(self.lastError!, privacy: .public)")
        }

        if let context = current {
            current = nil
            Task { await process(stopped.recording, in: stopped.directory, context: context) }
        }
    }

    /// Crea la Nota della Riunione nel Vault e la apre in Obsidian. Se non riesce la Riunione
    /// prosegue lo stesso: la nota verrà creata a fine Elaborazione.
    private func createMeetingNote(stenoID: UUID, startedAt: Date) -> URL? {
        guard let vault = Vault.configured else { return nil }
        do {
            let url = try vault.createMeetingNote(stenoID: stenoID, startedAt: startedAt)
            if Settings.openInObsidian {
                Task {
                    // Obsidian deve prima accorgersi del file nuovo.
                    try? await Task.sleep(for: .milliseconds(500))
                    Vault.openInObsidian(url)
                }
            }
            return url
        } catch {
            logger.error("Nota della Riunione non creata: \(error, privacy: .public)")
            lastError = "\(error.localizedDescription) La nota verrà creata a fine Elaborazione."
            return nil
        }
    }

    /// Elaborazione: Trascrizione, poi scrittura nel Vault (anche quando la Trascrizione fallisce,
    /// così la nota non resta su "Registrazione in corso").
    private func process(_ recording: Recording, in directory: URL, context: MeetingContext) async {
        processingCount += 1
        defer { processingCount -= 1 }
        // Con più Elaborazioni in parallelo, i link del menu seguono la Riunione più recente.
        let isLatest = directory == lastRecordingDirectory
        var problems: [String] = []

        let finished: MeetingTranscription.Finished?
        do {
            finished = try await context.transcription.finish(recording, in: directory)
        } catch {
            finished = nil
            problems.append("Trascrizione non riuscita: \(error.localizedDescription)")
        }
        if let finished {
            if isLatest { lastTranscriptURL = finished.url }
            if !finished.failedSegments.isEmpty {
                problems.append("Trascrizione incompleta: " + finished.failedSegments.joined(separator: "; "))
            }
        }

        if let vault = Vault.configured {
            do {
                let noteURL = try writeToVault(vault, finished, recording: recording, context: context)
                if isLatest { lastNoteURL = noteURL }
            } catch {
                problems.append("Scrittura nel Vault non riuscita: \(error.localizedDescription)")
            }
        }

        if !problems.isEmpty {
            lastError = problems.joined(separator: " ")
            logger.error("\(self.lastError!, privacy: .public)")
        } else if isLatest {
            lastError = nil
        }
    }

    private func writeToVault(
        _ vault: Vault, _ finished: MeetingTranscription.Finished?, recording: Recording, context: MeetingContext
    ) throws -> URL {
        let noteURL = try vault.findMeetingNote(stenoID: context.stenoID, expected: context.noteURL)
            ?? vault.createMeetingNote(stenoID: context.stenoID, startedAt: context.startedAt)
        guard let finished else {
            try vault.update(noteURL) {
                $0.recordFailure(stenoID: context.stenoID, reason: "Trascrizione non riuscita: la Registrazione è salvata, si potrà riprovare.")
            }
            return noteURL
        }
        let transcriptURL = try vault.writeTranscript(
            finished.transcript,
            stenoID: context.stenoID,
            meetingNoteName: noteURL.deletingPathExtension().lastPathComponent,
            language: finished.language
        )
        try vault.update(noteURL) {
            $0.recordTranscription(
                stenoID: context.stenoID,
                duration: recording.endedAt.timeIntervalSince(recording.startedAt),
                language: finished.language,
                provider: "Locale",
                transcriptName: transcriptURL.deletingPathExtension().lastPathComponent
            )
        }
        return noteURL
    }

    #if DEBUG
    /// Prove senza toccare il menu (l'esito finisce in `Steno/smoke-test.txt`, perché `log show` non è sempre leggibile):
    /// - `open Steno.app --args -smokeTestSeconds 20` registra per N secondi;
    /// - `open Steno.app --args -transcribeRecording <cartella>` rielabora una Registrazione esistente;
    /// - `-vaultPath <cartella>` usa un altro Vault, `-openInObsidian NO` non apre Obsidian.
    func runSmokeTestIfRequested() async {
        if let path = UserDefaults.standard.string(forKey: "transcribeRecording") {
            let directory = URL(filePath: path, directoryHint: .isDirectory)
            lastRecordingDirectory = directory
            do {
                let recording = try Recording.load(from: directory.appending(path: "riunione.json"))
                let context = MeetingContext(
                    stenoID: recording.meetingID,
                    startedAt: recording.startedAt,
                    noteURL: nil,
                    transcription: MeetingTranscription(transcriber: transcriber, language: Settings.forcedLanguage)
                )
                await process(recording, in: directory, context: context)
            } catch {
                lastError = error.localizedDescription
            }
            writeSmokeTestOutcome(lastTranscriptURL)
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
            to: URL.applicationSupportDirectory.appending(path: "Steno/smoke-test.txt"),
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
