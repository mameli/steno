import AVFoundation
import AppKit
import Carbon.HIToolbox
import Observation
import StenoCore
import os

private let logger = Logger(subsystem: "dev.mameli.steno", category: "meeting")

/// Starting and stopping the Meeting: permissions, recording, Meeting note, global shortcut.
/// At the stop the Meeting goes to `MeetingProcessor`, which processes it.
@MainActor
@Observable
final class MeetingController {
    /// When the Meeting in progress started; `nil` when idle.
    private var startedAt: Date?
    private let recorder = MeetingRecorder()
    let models = TranscriptionModels()
    private let transcriber: LocalTranscriber
    private let diarizer = SpeakerDiarizer()
    let processor: MeetingProcessor
    private var currentStenoID: UUID?
    private var now = Date()
    private var isRequestingPermission = false
    private var ticker: Task<Void, Never>?
    /// Menus being tracked. While the menu is open the timer does not touch observed state,
    /// otherwise every tick rebuilds its items (open submenus blink, the highlighted item loses
    /// its colour): it changes the title of the timer item in place instead.
    @ObservationIgnored private var openMenus = 0
    @ObservationIgnored private weak var openMenu: NSMenu?
    private var hotKey: GlobalHotKey?
    private var markHotKey: GlobalHotKey?
    /// False if another app already uses ⌃⌥⌘R.
    var isHotKeyAvailable: Bool { hotKey?.isRegistered ?? false }
    /// False if another app already uses ⌃⌥⌘M.
    var isMarkHotKeyAvailable: Bool { markHotKey?.isRegistered ?? false }
    /// The Recording folder of the Meeting in progress, where its Marks are saved.
    private var currentDirectory: URL?
    /// The Marks of the Meeting in progress, in seconds from its start.
    private(set) var marks: [TimeInterval] = []
    /// For a second after a Mark the menu bar shows a star instead of the red dot.
    private(set) var isShowingMark = false
    /// The transcription model while it is downloading or loading, as the menu shows it.
    private(set) var modelMenuTitle: String?
    /// The latest phase, also while a menu is open (the observed title waits for it to close).
    @ObservationIgnored private var modelPhase = ModelMenuPhase.notLoaded
    @ObservationIgnored private var latestModelMenuTitle: String?
    private(set) var microphoneDenied = false
    private(set) var recordingError: String?
    private(set) var lastRecordingDirectory: URL?
    /// Tracks of the Meeting in progress already notified as silent since the start.
    @ObservationIgnored private var silentTracksNotified: Set<Track> = []
    /// Template for the Meeting in progress or the next one; it can change until the stop.
    var templateName = AppSettings.defaultTemplate {
        didSet {
            if let currentStenoID { processor.templateChanged(stenoID: currentStenoID, to: templateName) }
        }
    }

    init() {
        transcriber = LocalTranscriber(models: models)
        AppSettings.registerDefaults()
        try? Vault.configured?.ensureDefaultTemplate()
        processor = MeetingProcessor(transcriber: transcriber, diarizer: diarizer)
        templateName = AppSettings.defaultTemplate
        Notifications.shared.configure()
        hotKey = GlobalHotKey(id: 1, keyCode: kVK_ANSI_R) { [weak self] in self?.toggle() }
        markHotKey = GlobalHotKey(id: 2, keyCode: kVK_ANSI_M) { [weak self] in self?.mark() }
        processor.resumeAfterLaunch()
        startDailyCleanUp()
        keepTimerLiveWithoutRebuildingMenus()
        Task { [transcriber] in
            await transcriber.setPhaseHandler { [weak self] phase in
                Task { @MainActor in self?.modelPhaseChanged(phase) }
            }
        }
        // Downloads started from Settings show in the menu too, only for the model in use.
        models.onProgress = { [weak self] model, percent in
            guard let self, model == .selected else { return }
            if let percent {
                modelPhaseChanged(.downloading(percent: percent))
            } else if case .downloading = modelPhase {
                // Downloaded from Settings: nothing loads it until the next Meeting.
                modelPhaseChanged(ModelMenuPhase.notLoaded)
            }
        }
    }

    var isInProgress: Bool { startedAt != nil }

    /// The error to show in the menu: the recording's or the last Processing's.
    var lastError: String? { recordingError ?? processor.lastError }

    /// Menu item with the timer of the Meeting in progress, `nil` if there is none.
    var recordingMenuTitle: String? { recordingMenuTitle(at: now) }

    private func recordingMenuTitle(at date: Date) -> String? {
        guard let startedAt else { return nil }
        return Self.recordingMenuTitle(elapsedLabel(max(0, date.timeIntervalSince(startedAt))))
    }

    private static func recordingMenuTitle(_ elapsed: String) -> String {
        String(localized: "Recording · \(elapsed)")
    }

    /// Menu lines for the Tracks of the Meeting in progress that have had no sound for 2 minutes or more.
    var silenceWarnings: [String] {
        guard let startedAt else { return [] }
        let elapsed = now.timeIntervalSince(startedAt)
        let lastSound = recorder.lastSoundTimes()
        return Track.allCases.compactMap { track in
            guard let trackLastSound = lastSound[track],
                  let minutes = TrackSilence.silentMinutes(lastSound: trackLastSound, now: elapsed)
            else { return nil }
            return switch track {
            case .me: String(localized: "⚠️ No sound from the microphone for \(minutes) min")
            case .others: String(localized: "⚠️ No sound from the system audio for \(minutes) min")
            }
        }
    }

    /// Once per Track per Meeting: a Track with no sound since the start means the Meeting would be lost.
    private func notifySilentTracks() {
        guard let startedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        for (track, lastSound) in recorder.lastSoundTimes()
        where !silentTracksNotified.contains(track) && TrackSilence.neverHeard(lastSound: lastSound, now: elapsed) {
            silentTracksNotified.insert(track)
            logger.error("No sound from the \(track.rawValue, privacy: .public) Track since the start")
            switch track {
            case .me:
                Notifications.shared.notify(
                    title: String(localized: "No sound from the microphone"),
                    body: String(localized: "Steno has recorded nothing from your microphone for 2 minutes. Check System Settings → Privacy & Security → Microphone."),
                    note: nil
                )
            case .others:
                Notifications.shared.notify(
                    title: String(localized: "No sound from the system audio"),
                    body: String(localized: "Steno has recorded nothing from the call for 2 minutes. Check System Settings → Privacy & Security → Screen & System Audio Recording."),
                    note: nil
                )
            }
        }
    }

    /// ⌃⌥⌘M or the menu: marks the current moment of the Meeting in progress as important. Saved at
    /// once, so a crash does not lose it; it stars the Transcript paragraph it falls in.
    func mark() {
        guard let startedAt, let currentDirectory else { return }
        marks.append(Date().timeIntervalSince(startedAt))
        do {
            try Marks.save(marks, inFolder: currentDirectory)
        } catch {
            logger.error("Mark not saved: \(error, privacy: .public)")
            recordingError = error.localizedDescription
        }
        // No sound: the system audio capture would record it in the Others Track.
        isShowingMark = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.isShowingMark = false
        }
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
        let model = TranscriptionModel.selected
        let transcription = MeetingTranscription(
            transcriber: transcriber, diarizer: diarizer, model: model, languages: AppSettings.meetingLanguages
        )
        let started: MeetingRecorder.Started
        do {
            started = try recorder.start(at: now) { segment, directory in
                Task { await transcription.segmentClosed(segment, in: directory) }
            }
        } catch {
            logger.error("Starting the recording failed: \(error, privacy: .public)")
            recordingError = error.localizedDescription
            return
        }
        startedAt = now
        recordingError = nil
        silentTracksNotified = []
        currentStenoID = started.meetingID
        currentDirectory = started.directory
        marks = []
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
                try await transcriber.prepare(model)
            } catch {
                logger.error("Preparing the model failed: \(error, privacy: .public)")
            }
        }
    }

    func stop() {
        guard isInProgress else {
            assertionFailure("Stop without a Meeting in progress")
            return
        }
        startedAt = nil
        ticker?.cancel()
        ticker = nil

        do {
            let stopped = try recorder.stop(at: Date())
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
        currentDirectory = nil
        marks = []
        templateName = AppSettings.defaultTemplate
    }

    /// Creates the Meeting note in the Vault and opens it in Obsidian. If that fails the Meeting
    /// goes on anyway: the note will be created at the end of Processing.
    private func createMeetingNote(stenoID: UUID, startedAt: Date) -> URL? {
        guard let vault = Vault.configured else { return nil }
        do {
            // Read after the recording has started: the calendar never delays it.
            let event = MeetingCalendar.eventInProgress(at: startedAt)
            let url = try vault.createMeetingNote(stenoID: stenoID, startedAt: startedAt, event: event)
            if AppSettings.openInObsidian {
                Vault.openNewFileInObsidian(url)
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
    /// - `open Steno.app --args -smokeTestSeconds 20` records for N seconds (with
    ///   `-simulateMicrophoneChangeAfter 5` the microphone restarts after 5 seconds, 2 of them silent);
    /// - `open Steno.app --args -transcribeRecording <folder>` reprocesses a Recording of the data folder;
    /// - `open Steno.app --args -regenerateMeeting <steno_id> -regenerateTemplate <name>` retries a Meeting
    ///   (only the Summary if its audio is deleted) with that Template and the active Profile;
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
            processor.retry(
                id, templateName: UserDefaults.standard.string(forKey: "regenerateTemplate") ?? templateName,
                profile: AppSettings.activeProviderProfile
            )
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
            let changeAfter = UserDefaults.standard.integer(forKey: "simulateMicrophoneChangeAfter")
            if changeAfter > 0, changeAfter < seconds {
                try? await Task.sleep(for: .seconds(changeAfter))
                recorder.simulateMicrophoneChange()
                try? await Task.sleep(for: .seconds(seconds - changeAfter))
            } else {
                try? await Task.sleep(for: .seconds(seconds))
            }
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

    private func keepTimerLiveWithoutRebuildingMenus() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] note in
            // Delivered on the main queue, where the menu lives.
            nonisolated(unsafe) let menu = note.object as? NSMenu
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.openMenus == 0 {
                    self.openMenu = menu
                    // Notes deleted or renamed in the Vault since the last time.
                    self.processor.refreshRecent()
                }
                self.openMenus += 1
            }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.openMenus = max(0, self.openMenus - 1)
                if self.openMenus == 0 { self.openMenu = nil }
                self.now = Date()
                if self.modelMenuTitle != self.latestModelMenuTitle { self.modelMenuTitle = self.latestModelMenuTitle }
            }
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.openMenus == 0 {
                    self.now = Date()
                } else {
                    self.updateOpenMenuTimer()
                }
                self.notifySilentTracks()
            }
        }
    }

    /// Like the timer, the model's progress changes the open menu's item in place: rebuilding the
    /// menu at every percent would make it blink. An item appearing or disappearing waits for the
    /// menu to close.
    private func modelPhaseChanged(_ phase: LocalTranscriber.ModelPhase) {
        switch phase {
        case .notLoaded: modelPhaseChanged(ModelMenuPhase.notLoaded)
        case .loading(_, let firstTime): modelPhaseChanged(.loading(firstTime: firstTime))
        case .ready: modelPhaseChanged(ModelMenuPhase.ready)
        }
    }

    private func modelPhaseChanged(_ phase: ModelMenuPhase) {
        // Progress reports can arrive after the download is over.
        if case .downloading = phase {
            switch modelPhase {
            case .loading, .ready: return
            case .notLoaded, .downloading: break
            }
        }
        modelPhase = phase
        let title = Self.modelMenuTitle(phase)
        // Whole percents only: the download reports progress many times a second.
        guard title != latestModelMenuTitle else { return }
        logger.info("Transcription model: \(title ?? "ready or not loaded", privacy: .public)")
        if openMenus == 0 {
            modelMenuTitle = title
        } else if let shown = latestModelMenuTitle, let title {
            openMenu?.items.first { $0.title == shown }?.title = title
        }
        latestModelMenuTitle = title
    }

    private static func modelMenuTitle(_ phase: ModelMenuPhase) -> String? {
        switch phase {
        case .notLoaded, .ready:
            nil
        case .downloading(let percent) where percent < 100:
            String(localized: "Downloading transcription model… \(percent)%")
        case .downloading, .loading(firstTime: true):
            String(localized: "Preparing transcription model, first time only: a few minutes…")
        case .loading(firstTime: false):
            String(localized: "Loading transcription model…")
        }
    }

    /// Another open menu (e.g. a picker in Settings) has no timer item: nothing changes.
    private func updateOpenMenuTimer() {
        guard let title = recordingMenuTitle(at: Date()) else { return }
        let prefix = Self.recordingMenuTitle("")
        openMenu?.items.first { $0.title.hasPrefix(prefix) }?.title = title
    }
}

/// What the menu says about the transcription model.
private enum ModelMenuPhase {
    case notLoaded
    case downloading(percent: Int)
    case loading(firstTime: Bool)
    case ready
}
