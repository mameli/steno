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
    private var machine = MeetingStateMachine()
    private let recorder = MeetingRecorder()
    private let transcriber = LocalTranscriber()
    private var transcription: MeetingTranscription?
    private var now = Date()
    private var isRequestingPermission = false
    private var ticker: Task<Void, Never>?
    private(set) var microphoneDenied = false
    private(set) var lastError: String?
    private(set) var lastRecordingDirectory: URL?
    private(set) var lastTranscriptURL: URL?
    private(set) var transcriptionsInProgress = 0

    // Finché non c'è una finestra impostazioni:
    // `defaults write dev.mameli.steno echoCancellation -bool false`
    // `defaults write dev.mameli.steno language it` (oppure `en`, `auto`)
    private var echoCancellation: Bool {
        UserDefaults.standard.bool(forKey: "echoCancellation")
    }

    /// `nil` per rilevare la lingua in automatico.
    private var forcedLanguage: String? {
        UserDefaults.standard.string(forKey: "language").flatMap {
            LocalTranscriber.supportedLanguages.contains($0) ? $0 : nil
        }
    }

    init() {
        UserDefaults.standard.register(defaults: ["echoCancellation": true, "language": "auto"])
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
        let transcription = MeetingTranscription(transcriber: transcriber, language: forcedLanguage)
        do {
            try recorder.start(at: now, echoCancellation: echoCancellation) { segment, directory in
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
        self.transcription = transcription
        lastError = nil
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

        if let transcription {
            self.transcription = nil
            Task { await transcribe(stopped.recording, in: stopped.directory, with: transcription) }
        }
    }

    private func transcribe(_ recording: Recording, in directory: URL, with transcription: MeetingTranscription) async {
        transcriptionsInProgress += 1
        defer { transcriptionsInProgress -= 1 }
        do {
            let finished = try await transcription.finish(recording, in: directory)
            // Con più Elaborazioni in parallelo, conta quella della Riunione più recente.
            if directory == lastRecordingDirectory {
                lastTranscriptURL = finished.url
            }
            if !finished.failedSegments.isEmpty {
                lastError = "Trascrizione incompleta: " + finished.failedSegments.joined(separator: "; ")
                logger.error("\(self.lastError!, privacy: .public)")
            }
        } catch {
            logger.error("Trascrizione fallita: \(error, privacy: .public)")
            lastError = "Trascrizione fallita: \(error.localizedDescription)"
        }
    }

    #if DEBUG
    /// Prove senza toccare il menu (l'esito finisce in `Steno/smoke-test.txt`, perché `log show` non è sempre leggibile):
    /// - `open Steno.app --args -smokeTestSeconds 20` registra per N secondi;
    /// - `open Steno.app --args -transcribeRecording <cartella>` ritrascrive una Registrazione esistente.
    func runSmokeTestIfRequested() async {
        if let path = UserDefaults.standard.string(forKey: "transcribeRecording") {
            let directory = URL(filePath: path, directoryHint: .isDirectory)
            lastRecordingDirectory = directory
            do {
                let recording = try Recording.load(from: directory.appending(path: "riunione.json"))
                let transcription = MeetingTranscription(transcriber: transcriber, language: forcedLanguage)
                await transcribe(recording, in: directory, with: transcription)
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
