import AVFoundation
import AppKit
import Observation
import StenoCore
import os

private let logger = Logger(subsystem: "dev.mameli.steno", category: "meeting")

/// Starting and stopping the Meeting: permissions, recording, Meeting note, global shortcut.
/// At the stop the Meeting goes to `MeetingProcessor`, which processes it.
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
    /// False if another app already uses ⌃⌥⌘R.
    var isHotKeyAvailable: Bool { hotKey?.isRegistered ?? false }
    private(set) var microphoneDenied = false
    private(set) var recordingError: String?
    private(set) var lastRecordingDirectory: URL?
    /// Template for the Meeting in progress or the next one; it can change until the stop.
    var templateName = AppSettings.defaultTemplate {
        didSet {
            if let currentStenoID { processor.templateChanged(stenoID: currentStenoID, to: templateName) }
        }
    }

    init() {
        AppSettings.registerDefaults()
        try? Vault.configured?.ensureDefaultTemplate()
        processor = MeetingProcessor(transcriber: transcriber)
        templateName = AppSettings.defaultTemplate
        Notifications.shared.configure()
        hotKey = GlobalHotKey { [weak self] in self?.toggle() }
        processor.resumeAfterLaunch()
        startDailyCleanUp()
    }

    var isInProgress: Bool { machine.state != .idle }

    /// The error to show in the menu: the recording's or the last Processing's.
    var lastError: String? { recordingError ?? processor.lastError }

    /// Timer of the Meeting in progress, `nil` if there is none.
    var elapsedText: String? {
        guard case .inProgress(let startedAt) = machine.state else { return nil }
        return elapsedLabel(max(0, now.timeIntervalSince(startedAt)))
    }

    /// ⌃⌥⌘R: starts or stops the Meeting from any app.
    func toggle() {
        if isInProgress {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        // The menu stays clickable while the permission prompt is open.
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
            logger.error("Starting the recording failed: \(error, privacy: .public)")
            recordingError = error.localizedDescription
            return
        }
        do {
            try machine.start(at: now)
        } catch {
            assertionFailure("Start with a Meeting already in progress: \(error)")
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

        // On first use this downloads the model: better while the Meeting is in progress.
        Task { [transcriber] in
            do {
                try await transcriber.prepare()
            } catch {
                logger.error("Preparing the model failed: \(error, privacy: .public)")
            }
        }
    }

    func stop() {
        let interval: DateInterval
        do {
            interval = try machine.stop(at: Date())
        } catch {
            assertionFailure("Stop without a Meeting in progress: \(error)")
            return
        }
        ticker?.cancel()
        ticker = nil

        do {
            let stopped = try recorder.stop(at: interval.end)
            lastRecordingDirectory = stopped.directory
            if !stopped.errors.isEmpty {
                recordingError = String(localized: "Incomplete recording: \(stopped.errors.joined(separator: "; "))")
                logger.error("\(self.recordingError!, privacy: .public)")
            }
        } catch {
            logger.error("Closing the recording failed: \(error, privacy: .public)")
            recordingError = error.localizedDescription
        }
        if let currentStenoID {
            processor.meetingStopped(stenoID: currentStenoID)
        }
        currentStenoID = nil
        templateName = AppSettings.defaultTemplate
    }

    /// Creates the Meeting note in the Vault and opens it in Obsidian. If that fails the Meeting
    /// goes on anyway: the note will be created at the end of Processing.
    private func createMeetingNote(stenoID: UUID, startedAt: Date) -> URL? {
        guard let vault = Vault.configured else { return nil }
        do {
            let url = try vault.createMeetingNote(stenoID: stenoID, startedAt: startedAt)
            if AppSettings.openInObsidian {
                Task {
                    // Obsidian must notice the new file first.
                    try? await Task.sleep(for: .milliseconds(500))
                    Vault.openInObsidian(url)
                }
            }
            return url
        } catch {
            logger.error("Meeting note not created: \(error, privacy: .public)")
            recordingError = String(localized: "\(error.localizedDescription) The note will be created at the end of Processing.")
            return nil
        }
    }

    /// Expired audio is deleted at launch and then once a day.
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
    /// Tests without touching the menu (the outcome goes to `smoke-test.txt` next to the data
    /// folder, because `log show` is not always readable):
    /// - `open Steno.app --args -smokeTestSeconds 20` records for N seconds;
    /// - `open Steno.app --args -transcribeRecording <folder>` reprocesses a Recording of the data folder;
    /// - `open Steno.app --args -regenerateMeeting <steno_id> -regenerateTemplate <name>` regenerates the Summary;
    /// - always together with `-vaultPath <folder>`, `-testSummaryBaseURL <url>` and `-dataDirectory <folder>`,
    ///   otherwise the test refuses to start; `-openInObsidian NO` does not open Obsidian.
    func runSmokeTestIfRequested() async {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        let isTest = ["smokeTestSeconds", "transcribeRecording", "regenerateMeeting"].contains { arguments[$0] != nil }
        let isIsolated = ["vaultPath", "testSummaryBaseURL", "dataDirectory"].allSatisfy { arguments[$0] != nil }
        guard !isTest || isIsolated else {
            // An automated test without isolation would write to the real Vault with the real Provider.
            recordingError = "Automated test refused: -vaultPath, -testSummaryBaseURL and -dataDirectory are required."
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
        let outcome = lastError.map { "error: \($0)" } ?? "ok: \(url?.path ?? "-")"
        try? outcome.write(
            to: MeetingRecorder.recordingsDirectory.deletingLastPathComponent().appending(path: "smoke-test.txt"),
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
