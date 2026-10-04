import AVFoundation
import AppKit
import Observation
import StenoCore

/// Collega la macchina a stati della Riunione alla UI e ai permessi di sistema.
@MainActor
@Observable
final class MeetingController {
    private var machine = MeetingStateMachine()
    private var now = Date()
    private var isRequestingPermission = false
    private var ticker: Task<Void, Never>?
    private(set) var microphoneDenied = false

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
            try machine.start(at: now)
        } catch {
            assertionFailure("Avvio con una Riunione già in corso: \(error)")
            return
        }
        startTicker()
    }

    func stop() {
        do {
            _ = try machine.stop(at: Date())
        } catch {
            assertionFailure("Stop senza una Riunione in corso: \(error)")
        }
        ticker?.cancel()
        ticker = nil
    }

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
