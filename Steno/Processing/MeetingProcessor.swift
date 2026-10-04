import Foundation
import StenoCore
import os

private let logger = Logger(subsystem: "dev.mameli.steno", category: "processing")

/// Meeting Processing: one at a time, in arrival order, with the state saved in the Recording
/// folder (`processing.json`) so it resumes after a restart or a crash. Also handles Retry,
/// Regeneration, notifications and audio retention.
@MainActor
@Observable
final class MeetingProcessor {
    struct RecentMeeting: Identifiable {
        let id: UUID
        let title: String
        let status: ProcessingRecord.Status
        /// The audio is still there: the full Processing can be retried.
        let hasAudio: Bool
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
    private(set) var lastTranscriptURL: URL?

    init(transcriber: LocalTranscriber) {
        self.transcriber = transcriber
    }

    static func directory(for stenoID: UUID) -> URL {
        MeetingRecorder.meetingsDirectory.appending(path: stenoID.uuidString, directoryHint: .isDirectory)
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

    /// Redoes the whole Processing (Segments already transcribed come from the cache).
    /// Only for concluded Meetings: one being recorded or already queued is left alone.
    func retry(_ stenoID: UUID) {
        guard var record = record(stenoID), (try? record.queueForRetry()) != nil else { return }
        save(record)
        enqueueProcessing(record)
    }

    /// New Summary with another Template or Profile, from the Transcript in the Vault:
    /// works even after the audio has been deleted. The Template and Profile chosen at the
    /// start remain the Meeting's (Retry uses them).
    func regenerate(_ stenoID: UUID, templateName: String? = nil, profile: ProviderProfile? = nil) {
        guard var record = record(stenoID), (try? record.beginRegeneration()) != nil else { return }
        save(record)
        enqueue { await self.runRegeneration(record, templateName: templateName, profile: profile) }
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
        retry(recording.meetingID)
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
            ?? MeetingTranscription(transcriber: transcriber, language: AppSettings.forcedLanguage)

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

    private func runRegeneration(_ queued: ProcessingRecord, templateName: String?, profile: ProviderProfile?) async {
        var record = queued
        let stenoID = record.stenoID
        guard let vault = Vault.configured,
              let noteURL = vault.findMeetingNote(stenoID: stenoID, expected: record.noteURL),
              let transcriptURL = vault.findTranscript(stenoID: stenoID),
              let transcriptFile = try? String(contentsOf: transcriptURL, encoding: .utf8)
        else {
            finish(&record, problems: [String(localized: "Regeneration not possible: Meeting note or Transcript not found in the Vault.")], warnings: [])
            return
        }

        var problems: [String] = []
        do {
            let (transcript, language) = Transcript.parse(vaultFile: transcriptFile)
            let (summary, _) = await summarize(
                transcript, language: language,
                personalNotes: try vault.meetingNote(at: noteURL).personalNotes,
                template: vault.template(named: templateName ?? record.templateName),
                profile: profile ?? record.summaryProfile,
                wantsTitle: false
            )
            try vault.update(noteURL) {
                $0.recordRegeneration(
                    stenoID: stenoID, transcriptName: transcriptURL.deletingPathExtension().lastPathComponent, summary: summary
                )
            }
            if case .failed(let reason) = summary { problems.append(String(localized: "Summary not generated: \(reason)")) }
            record.noteURL = noteURL
            lastNoteURL = noteURL
        } catch {
            problems.append(String(localized: "Regeneration failed: \(error.localizedDescription)"))
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
                Notifications.shared.notify(title: String(localized: "Summary ready"), body: body, note: record.noteURL)
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
        var noteURL = try vault.findMeetingNote(stenoID: record.stenoID, expected: record.noteURL)
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

        let (summary, title) = await summarize(
            finished.transcript, language: finished.language,
            personalNotes: try vault.meetingNote(at: noteURL).personalNotes,
            template: vault.template(named: record.templateName), profile: record.summaryProfile,
            wantsTitle: true
        )
        // Only a note still in place and with its provisional name is renamed. If the rename
        // fails the note stays as it is: the Summary must not be lost over a name.
        if let title, vault.isInMeetingsFolder(noteURL),
           let newName = VaultNaming.renamedNoteName(
               current: noteURL.deletingPathExtension().lastPathComponent, startedAt: record.startedAt, title: title
           ) {
            do {
                noteURL = try vault.rename(noteURL, to: newName)
            } catch {
                logger.error("Renaming the note failed: \(error, privacy: .public)")
            }
        }

        let transcriptURL = try vault.writeTranscript(
            finished.transcript,
            stenoID: record.stenoID,
            meetingNoteName: noteURL.deletingPathExtension().lastPathComponent,
            language: finished.language
        )
        try vault.update(noteURL) {
            $0.recordProcessing(
                stenoID: record.stenoID,
                duration: recording.endedAt.timeIntervalSince(recording.startedAt),
                language: finished.language,
                transcriptionProvider: "Local",
                transcriptName: transcriptURL.deletingPathExtension().lastPathComponent,
                summary: summary
            )
        }
        if case .failed(let reason) = summary {
            return (noteURL, String(localized: "Summary not generated: \(reason)"))
        }
        return (noteURL, nil)
    }

    /// Summary and, when needed for the rename, title. A missing title is not an error:
    /// the note keeps its provisional name.
    private func summarize(
        _ transcript: Transcript, language: String?, personalNotes: String, template: Template,
        profile: ProviderProfile?, wantsTitle: Bool
    ) async -> (MeetingNote.SummaryOutcome, String?) {
        #if DEBUG
        let profile = AppSettings.testSummaryProfile ?? profile
        #endif
        guard let profile else {
            return (.failed(reason: ProfileError.noActiveProfile.localizedDescription), nil)
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
            let reply = wantsTitle
                ? try? await client.complete(MeetingTitle.request(summary: text, language: prompt.summaryLanguage))
                : nil
            return (.written(text: text, template: template.name, provider: profile.displayName), reply.flatMap(MeetingTitle.clean))
        } catch {
            logger.error("Summary not generated: \(error, privacy: .public)")
            return (.failed(reason: error.localizedDescription), nil)
        }
    }

    // MARK: - State on disk

    private func record(_ stenoID: UUID) -> ProcessingRecord? {
        try? ProcessingRecord.load(from: Self.directory(for: stenoID))
    }

    private func save(_ record: ProcessingRecord) {
        do {
            try record.save(in: Self.directory(for: record.stenoID))
        } catch {
            logger.error("Processing state not saved: \(error, privacy: .public)")
            lastError = String(localized: "Meeting state not saved to disk: a restart now would not resume it. \(error.localizedDescription)")
        }
        refreshRecent()
    }

    private func allRecords() -> [ProcessingRecord] {
        recordingFolders().compactMap { try? ProcessingRecord.load(from: $0) }
    }

    private func recordingFolders() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: MeetingRecorder.meetingsDirectory, includingPropertiesForKeys: nil)) ?? []
    }

    func refreshRecent() {
        recent = allRecords()
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(5)
            .map { record in
                let title = record.noteURL?.deletingPathExtension().lastPathComponent
                    ?? record.startedAt.formatted(date: .abbreviated, time: .shortened)
                return RecentMeeting(
                    id: record.stenoID, title: title, status: record.status,
                    hasAudio: Self.hasAudio(Self.directory(for: record.stenoID))
                )
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

    /// Deletes the audio files of expired Recordings, with the transcription caches and the
    /// `transcript.md` copy. The manifests stay: the Meeting stays among the recent ones and
    /// can be Regenerated from the Transcript in the Vault.
    func cleanUpExpiredRecordings() {
        let items = recordingFolders().compactMap { folder -> Retention.Item? in
            guard let stenoID = UUID(uuidString: folder.lastPathComponent) else { return nil }
            let record = try? ProcessingRecord.load(from: folder)
            guard let startedAt = record?.startedAt ?? (try? Recording.load(fromFolder: folder))?.startedAt else { return nil }
            return Retention.Item(stenoID: stenoID, startedAt: startedAt, status: record?.status)
        }
        let kept = Set([
            Recording.fileName, Recording.legacyFileName, ProcessingRecord.fileName, ProcessingRecord.legacyFileName,
        ] + Track.allCases.map(Segment.listFileName(for:)))
        for stenoID in Retention.expired(items, now: Date(), days: AppSettings.retentionDays) {
            let folder = Self.directory(for: stenoID)
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where !kept.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        refreshRecent()
    }
}
