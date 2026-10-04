import AVFoundation
import AppKit
import Observation
import StenoCore
import os

private let logger = Logger(subsystem: "dev.mameli.steno", category: "riunione")

/// Collega la macchina a stati della Riunione alla UI, ai permessi di sistema e alla registrazione.
@MainActor
@Observable
final class MeetingController {
    private var machine = MeetingStateMachine()
    private let recorder = MeetingRecorder()
    private var now = Date()
    private var isRequestingPermission = false
    private var ticker: Task<Void, Never>?
    private(set) var microphoneDenied = false
    private(set) var lastError: String?
    private(set) var lastRecordingDirectory: URL?

    /// Finché non c'è una finestra impostazioni: `defaults write dev.mameli.steno echoCancellation -bool false`.
    private var echoCancellation: Bool {
        UserDefaults.standard.bool(forKey: "echoCancellation")
    }

    init() {
        UserDefaults.standard.register(defaults: ["echoCancellation": true])
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
        do {
            try recorder.start(at: now, echoCancellation: echoCancellation)
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
        startTicker()
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
            lastRecordingDirectory = try recorder.stop(at: interval.end)
        } catch let incomplete as MeetingRecorder.IncompleteRecording {
            logger.error("\(incomplete.localizedDescription, privacy: .public)")
            lastRecordingDirectory = incomplete.directory
            lastError = incomplete.localizedDescription
        } catch {
            logger.error("Chiusura della registrazione fallita: \(error, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    #if DEBUG
    /// `open Steno.app --args -smokeTestSeconds 20`: registra per N secondi senza toccare il menu.
    func runSmokeTestIfRequested() async {
        let seconds = UserDefaults.standard.integer(forKey: "smokeTestSeconds")
        guard seconds > 0 else { return }
        await start()
        if isInProgress {
            try? await Task.sleep(for: .seconds(seconds))
            stop()
        }
        // `log show` non è sempre leggibile: l'esito va anche su file.
        let outcome = lastError.map { "errore: \($0)" } ?? "ok: \(lastRecordingDirectory?.path ?? "-")"
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
