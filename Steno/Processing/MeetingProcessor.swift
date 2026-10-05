import AppKit
import Foundation
import StenoCore
import os

private let logger = Logger(subsystem: "dev.mameli.steno", category: "processing")

/// Meeting Processing: one at a time, in arrival order, with the state saved in the Recording
/// folder (`processing.json`) so it resumes after a restart or a crash. Also handles Retry,
/// notifications and audio retention.
@MainActor
@Observable
final class MeetingProcessor {
    struct RecentMeeting: Identifiable {
        let id: UUID
        let title: String
        let status: ProcessingRecord.Status
    }

    private let transcriber: LocalTranscriber
    /// Transcriptions started while recording, to be completed at the stop.
    private var liveTranscriptions: [UUID: MeetingTranscription] = [:]
    /// In-memory copy of the state of Meetings being recorded: if saving to disk fails,
    /// the Meeting is still queued at the stop.
    private var recordingRecords: [UUID: ProcessingRecord] = [:]
    /// The last Processing in the queue: the next one starts when this one ends.
    private var queueTail: Task<Void, Never>?
    private(set) var pendingCount = 0
    private(set) var lastError: String?
    private(set) var recent: [RecentMeeting] = []
    private(set) var lastNoteURL: URL?
    /// The Transcript in the Vault or, without a Vault, the copy in the Recording folder.
    private(set) var lastTranscriptURL: URL?

    init(transcriber: LocalTranscriber) {
        self.transcriber = transcriber
    }

    static func directory(for stenoID: UUID) -> URL {
        MeetingRecorder.recordingsDirectory.appending(path: stenoID.uuidString, directoryHint: .isDirectory)
    }

    // MARK: - Meeting lifecycle

    func meetingStarted(
        stenoID: UUID, startedAt: Date, templateName: String, summaryProfile: ProviderProfile?,
        noteURL: URL?, transcription: MeetingTranscription
    ) {
        liveTranscriptions[stenoID] = transcription
        let record = ProcessingRecord(
            stenoID: stenoID, startedAt: startedAt, status: .recording,
            templateName: templateName, summaryProfile: summaryProfile, noteURL: noteURL
        )
        recordingRecords[stenoID] = record
        save(record)
    }

    func templateChanged(stenoID: UUID, to templateName: String) {
        guard var record = recordingRecords[stenoID] else { return }
        record.templateName = templateName
        recordingRecords[stenoID] = record
        save(record)
    }

    func meetingStopped(stenoID: UUID) {
        guard var record = recordingRecords.removeValue(forKey: stenoID) ?? record(stenoID) else { return }
        record.status = .queued
        save(record)
        enqueueProcessing(record)
    }

    /// After a restart: resumes Processing left halfway and recovers Recordings interrupted
    /// by a crash, then deletes expired audio.
    func resumeAfterLaunch() {
        let plan = ProcessingRecord.afterRestart(allRecords())
        plan.toSave.forEach(save)
        for var record in plan.toProcess {
            if record.status == .recording {
                do {
                    try recoverRecording(record, in: Self.directory(for: record.stenoID))
                } catch {
                    record.status = .failed(reason: String(localized: "Recording interrupted and not recoverable: \(error.localizedDescription)"))
                    save(record)
                    continue
                }
            }
            record.status = .queued
            save(record)
            enqueueProcessing(record)
        }
        cleanUpExpiredRecordings()
    }

    // MARK: - Actions from the Recent meetings menu

    func openNote(_ stenoID: UUID) {
        guard let vault = Vault.configured,
              let note = vault.findMeetingNote(stenoID: stenoID, expected: record(stenoID)?.noteURL)
        else {
            lastError = String(localized: "Meeting note not found in the Vault.")
            return
        }
        Vault.openInObsidian(note)
    }

    /// In Obsidian like the notes; the copy in the Recording folder (no Vault) with the default app.
    func openLastTranscript() {
        guard let url = lastTranscriptURL else { return }
        if let vault = Vault.configured, url.path(percentEncoded: false).hasPrefix(vault.root.path(percentEncoded: false)) {
            Vault.openInObsidian(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Retry, with the Template and Profile chosen in the menu now: they become the Meeting's.
    /// With the audio still there the whole Processing is redone (Segments already transcribed
    /// come from the cache); once the audio is deleted, only the Summary is made again from the
    /// Transcript in the Vault (a Regeneration). Only for concluded Meetings: one being recorded
    /// or already queued is left alone.
    func retry(_ stenoID: UUID, templateName: String, profile: ProviderProfile?) {
        guard var record = record(stenoID) else { return }
        record.templateName = templateName
        record.summaryProfile = profile
        if Self.hasAudio(Self.directory(for: stenoID)) {
            guard (try? record.queueForRetry()) != nil else { return }
            save(record)
            enqueueProcessing(record)
        } else {
            guard (try? record.beginRegeneration()) != nil else { return }
            save(record)
            enqueue { await self.runRegeneration(record) }
        }
    }

    #if DEBUG
    /// Reprocesses a Recording of the data folder (automated tests) and waits for the end.
    func reprocess(_ directory: URL) async -> URL? {
        guard let recording = try? Recording.load(fromFolder: directory),
              Self.directory(for: recording.meetingID).standardizedFileURL == directory.standardizedFileURL
        else {
            lastError = "Reprocessing refused: the folder is not in Steno's data folder."
            return nil
        }
        if record(recording.meetingID) == nil {
            save(ProcessingRecord(
                stenoID: recording.meetingID, startedAt: recording.startedAt, status: .completed,
                templateName: AppSettings.defaultTemplate, summaryProfile: AppSettings.activeProviderProfile, noteURL: nil
            ))
        }
        retry(
            recording.meetingID,
            templateName: record(recording.meetingID)?.templateName ?? AppSettings.defaultTemplate,
            profile: AppSettings.activeProviderProfile
        )
        await waitUntilIdle()
        return lastTranscriptURL
    }

    func waitUntilIdle() async {
        await queueTail?.value
    }
    #endif

    // MARK: - Queue

    private func enqueueProcessing(_ record: ProcessingRecord) {
        enqueue { await self.process(record) }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        pendingCount += 1
        let previous = queueTail
        queueTail = Task {
            await previous?.value
            await work()
            pendingCount -= 1
        }
    }

    private func process(_ queued: ProcessingRecord) async {
        // The state on disk may be newer (e.g. Template changed), otherwise the queued one applies.
        var record = record(queued.stenoID) ?? queued
        record.status = .processing
        save(record)
        let directory = Self.directory(for: record.stenoID)
        let transcription = liveTranscriptions.removeValue(forKey: record.stenoID)
            ?? MeetingTranscription(transcriber: transcriber, model: .selected, language: AppSettings.forcedLanguage)

        let recording: Recording
        do {
            recording = try Recording.load(fromFolder: directory)
        } catch {
            finish(&record, problems: [String(localized: "Recording unreadable: \(error.localizedDescription)")], warnings: [])
            return
        }

        var problems: [String] = []
        // An unreadable Segment (e.g. the one open during a crash) leaves a gap in the
        // Transcript but does not prevent the Summary: it is a warning, not a failure.
        var warnings: [String] = []
        let finished: MeetingTranscription.Finished?
        do {
            finished = try await transcription.finish(recording, in: directory)
            if let failedSegments = finished?.failedSegments, !failedSegments.isEmpty {
                warnings.append(String(localized: "Incomplete transcript: \(failedSegments.joined(separator: "; "))"))
            }
            lastTranscriptURL = finished?.url
        } catch {
            finished = nil
            problems.append(String(localized: "Transcription failed: \(error.localizedDescription)"))
        }

        if let vault = Vault.configured {
            do {
                let (noteURL, summaryProblem) = try await writeToVault(vault, finished, recording: recording, record: record)
                record.noteURL = noteURL
                lastNoteURL = noteURL
                if let summaryProblem { problems.append(summaryProblem) }
            } catch {
                problems.append(String(localized: "Writing to the Vault failed: \(error.localizedDescription)"))
            }
        } else {
            warnings.append(String(localized: "No Vault configured: no Summary, the Transcript is only in the Recording folder."))
        }
        finish(&record, problems: problems, warnings: warnings)
    }

    private func runRegeneration(_ queued: ProcessingRecord) async {
        var record = queued
        let stenoID = record.stenoID
        guard let vault = Vault.configured,
              var noteURL = vault.findMeetingNote(stenoID: stenoID, expected: record.noteURL),
              let transcriptURL = vault.findTranscript(stenoID: stenoID),
              let transcriptFile = try? String(contentsOf: transcriptURL, encoding: .utf8)
        else {
            finish(&record, problems: [String(localized: "Retry not possible: the audio is deleted and the Meeting note or Transcript is not in the Vault.")], warnings: [])
            return
        }

        var problems: [String] = []
        do {
            let (transcript, language) = Transcript.parse(vaultFile: transcriptFile)
            let summaryProblem: String?
            (noteURL, summaryProblem) = try await writeSummary(
                transcript, language: language, into: noteURL, record: record, vault: vault
            ) { noteURL, summary in
                try vault.update(noteURL) {
                    $0.recordRegeneration(
                        stenoID: stenoID, transcriptName: transcriptURL.deletingPathExtension().lastPathComponent, summary: summary
                    )
                }
            }
            if let summaryProblem { problems.append(summaryProblem) }
            record.noteURL = noteURL
            lastNoteURL = noteURL
        } catch {
            problems.append(String(localized: "Retry failed: \(error.localizedDescription)"))
        }
        finish(&record, problems: problems, warnings: [])
    }

    private func finish(_ record: inout ProcessingRecord, problems: [String], warnings: [String]) {
        let noteName = record.noteURL?.deletingPathExtension().lastPathComponent ?? String(localized: "Meeting")
        if problems.isEmpty {
            record.status = .completed
            lastError = warnings.isEmpty ? nil : warnings.joined(separator: " ")
            if Vault.configured == nil {
                Notifications.shared.notify(
                    title: String(localized: "Transcript ready"),
                    body: String(localized: "Set up the Vault to get the Summary."), note: nil
                )
            } else {
                let body = warnings.isEmpty ? noteName : "\(noteName) (\(warnings.joined(separator: " ")))"
                let title = record.summaryProfile == nil ? String(localized: "Transcript ready") : String(localized: "Summary ready")
                Notifications.shared.notify(title: title, body: body, note: record.noteURL)
            }
        } else {
            let reason = problems.joined(separator: " ")
            record.status = .failed(reason: reason)
            lastError = reason
            logger.error("\(reason, privacy: .public)")
            Notifications.shared.notify(
                title: String(localized: "Processing failed"), body: "\(noteName): \(reason)", note: record.noteURL
            )
        }
        save(record)
    }

    // MARK: - Vault and Summary

    /// Writes the outcome of Processing into the Vault: Summary, title and rename, Transcript,
    /// Meeting note. Returns the note and, if there was one, the Summary problem.
    private func writeToVault(
        _ vault: Vault, _ finished: MeetingTranscription.Finished?, recording: Recording, record: ProcessingRecord
    ) async throws -> (URL, String?) {
        let noteURL = try vault.findMeetingNote(stenoID: record.stenoID, expected: record.noteURL)
            ?? vault.createMeetingNote(stenoID: record.stenoID, startedAt: record.startedAt)
        guard let finished else {
            try vault.update(noteURL) {
                $0.recordFailure(
                    stenoID: record.stenoID,
                    reason: String(localized: "Transcription failed: the Recording is saved, you can retry.")
                )
            }
            return (noteURL, nil)
        }

        return try await writeSummary(
            finished.transcript, language: finished.language, into: noteURL, record: record, vault: vault
        ) { noteURL, summary in
            // Written after the rename: a new Transcript is named after the note's final name.
            let transcriptURL = try vault.writeTranscript(
                finished.transcript,
                stenoID: record.stenoID,
                meetingNoteName: noteURL.deletingPathExtension().lastPathComponent,
                language: finished.language
            )
            lastTranscriptURL = transcriptURL
            try vault.update(noteURL) {
                $0.recordProcessing(
                    stenoID: record.stenoID,
                    duration: recording.endedAt.timeIntervalSince(recording.startedAt),
                    language: finished.language,
                    transcriptName: transcriptURL.deletingPathExtension().lastPathComponent,
                    summary: summary
                )
            }
        }
    }

    /// Generates the Summary with the Meeting's Template and Profile, renames a note still
    /// provisional with the title, lets `writeNote` write the note where it now is, and shows the
    /// renamed note in Obsidian. Returns where the note is and the Summary problem, if any.
    private func writeSummary(
        _ transcript: Transcript, language: String?, into noteURL: URL, record: ProcessingRecord, vault: Vault,
        writeNote: (URL, MeetingNote.SummaryOutcome) throws -> Void
    ) async throws -> (URL, String?) {
        let (summary, title) = await summarize(
            transcript, language: language,
            personalNotes: try vault.meetingNote(at: noteURL).personalNotes,
            template: vault.template(named: record.templateName), profile: record.summaryProfile
        )
        let rename = renameIfProvisional(noteURL, title: title, startedAt: record.startedAt, in: vault)
        try writeNote(rename.url, summary)
        if rename.follow { RenamedNoteFollower.follow(rename.url, in: vault) }
        if case .failed(let reason) = summary {
            return (rename.url, String(localized: "Summary not generated: \(reason)"))
        }
        return (rename.url, nil)
    }

    /// Renames with the title a note still in place and with its provisional name. Returns where
    /// the note is and whether Obsidian must be shown the renamed note (it was showing it). If the
    /// rename fails the note stays as it is: the Summary must not be lost over a name.
    private func renameIfProvisional(
        _ noteURL: URL, title: String?, startedAt: Date, in vault: Vault
    ) -> (url: URL, follow: Bool) {
        guard let title, vault.isInMeetingsFolder(noteURL),
              let newName = VaultNaming.renamedNoteName(
                  current: noteURL.deletingPathExtension().lastPathComponent, startedAt: startedAt, title: title
              )
        else { return (noteURL, false) }
        // Read before the rename: afterwards Obsidian may already show another note.
        let wasShownInObsidian = vault.isShownInObsidian(noteURL) ?? true
        do {
            let renamed = try vault.rename(noteURL, to: newName)
            return (renamed, wasShownInObsidian && AppSettings.openInObsidian)
        } catch {
            logger.error("Renaming the note failed: \(error, privacy: .public)")
            return (noteURL, false)
        }
    }

    /// Summary and title for the rename. A missing title is not an error: the note keeps its
    /// provisional name.
    private func summarize(
        _ transcript: Transcript, language: String?, personalNotes: String, template: Template,
        profile: ProviderProfile?
    ) async -> (MeetingNote.SummaryOutcome, String?) {
        var profile = profile
        var isTestProfile = false
        #if DEBUG
        if let testProfile = AppSettings.testSummaryProfile {
            profile = testProfile
            isTestProfile = true
        }
        #endif
        // No Profile chosen ("Transcript" in the menu): no Summary and no Template, only the Transcript.
        guard let profile else { return (.transcriptOnly, nil) }
        // A Profile deleted after the Meeting started has lost its key in the Keychain too.
        guard isTestProfile || AppSettings.summaryProfiles.contains(where: { $0.id == profile.id }) else {
            return (.failed(reason: String(localized: "the Profile \"\(profile.displayName)\" was deleted: choose another one in the menu and Retry.")), nil)
        }
        guard !transcript.paragraphs.isEmpty else {
            return (.failed(reason: String(localized: "there is no speech in the Recording.")), nil)
        }
        do {
            let client = try ChatClient(profile: profile)
            let prompt = SummaryPrompt(
                template: template, personalNotes: personalNotes, transcript: transcript, meetingLanguage: language
            )
            let text = try await Summarizer(client: client, maxContextTokens: profile.maxContextTokens).summarize(prompt)
            let reply = try? await client.complete(MeetingTitle.request(summary: text, language: prompt.summaryLanguage))
            return (.written(text: text, template: template.name, provider: profile.displayName), reply.flatMap(MeetingTitle.clean))
        } catch {
            logger.error("Summary not generated: \(error, privacy: .public)")
            return (.failed(reason: error.localizedDescription), nil)
        }
    }

    // MARK: - State on disk

    private func record(_ stenoID: UUID) -> ProcessingRecord? {
        try? ProcessingRecord.load(fromFolder: Self.directory(for: stenoID))
    }

    private func save(_ record: ProcessingRecord) {
        do {
            try record.save(inFolder: Self.directory(for: record.stenoID))
        } catch {
            logger.error("Processing state not saved: \(error, privacy: .public)")
            lastError = String(localized: "Meeting state not saved to disk: a restart now would not resume it. \(error.localizedDescription)")
        }
        refreshRecent()
    }

    private func allRecords() -> [ProcessingRecord] {
        recordingFolders().compactMap { try? ProcessingRecord.load(fromFolder: $0) }
    }

    private func recordingFolders() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: MeetingRecorder.recordingsDirectory, includingPropertiesForKeys: nil)) ?? []
    }

    func refreshRecent() {
        recent = allRecords()
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(5)
            .map { record in
                let title = record.noteURL?.deletingPathExtension().lastPathComponent
                    ?? record.startedAt.formatted(date: .abbreviated, time: .shortened)
                return RecentMeeting(id: record.stenoID, title: title, status: record.status)
            }
    }

    private static func hasAudio(_ directory: URL) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.contains { $0.pathExtension == "m4a" }
    }

    /// Rebuilds `recording.json` of a Recording interrupted by a crash from the Segment
    /// lists; the end is the last write of a Segment.
    private func recoverRecording(_ record: ProcessingRecord, in directory: URL) throws {
        let segments = Track.allCases.flatMap { track -> [Segment] in
            let url = directory.appending(path: Segment.listFileName(for: track))
            return (try? JSONDecoder().decode([Segment].self, from: Data(contentsOf: url))) ?? []
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )
        let lastWrite = files
            .filter { $0.pathExtension == "m4a" }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max() ?? record.startedAt
        try Recording.recovered(stenoID: record.stenoID, startedAt: record.startedAt, segments: segments, lastWrite: lastWrite)
            .save(inFolder: directory)
    }

    /// Deletes the audio of expired Recordings (see `deleteAudio(olderThanDays:)`).
    func cleanUpExpiredRecordings() {
        Self.deleteAudio(olderThanDays: AppSettings.retentionDays)
        refreshRecent()
    }

    /// Deletes the audio files of concluded Recordings older than `days` days (0: all of them),
    /// with the transcription caches and the `transcript.md` copy. Meetings still pending are
    /// kept. The manifests stay: the Meeting stays among the recent ones and Retry makes the
    /// Summary again from the Transcript in the Vault.
    static func deleteAudio(olderThanDays days: Int) {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: MeetingRecorder.recordingsDirectory, includingPropertiesForKeys: nil
        )) ?? []
        let items = folders.compactMap { folder -> Retention.Item? in
            guard let stenoID = UUID(uuidString: folder.lastPathComponent) else { return nil }
            guard let record = try? ProcessingRecord.load(fromFolder: folder) else { return nil }
            return Retention.Item(stenoID: stenoID, startedAt: record.startedAt, status: record.status)
        }
        let kept = Set([Recording.fileName, ProcessingRecord.fileName] + Track.allCases.map(Segment.listFileName(for:)))
        for stenoID in Retention.expired(items, now: Date(), days: days) {
            let folder = directory(for: stenoID)
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where !kept.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Bytes of audio kept, shown in Settings.
    static func audioSize() -> Int64 {
        let enumerator = FileManager.default.enumerator(
            at: MeetingRecorder.recordingsDirectory, includingPropertiesForKeys: [.fileSizeKey]
        )
        var total: Int64 = 0
        while let file = enumerator?.nextObject() as? URL {
            if file.pathExtension == "m4a" {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }
}
