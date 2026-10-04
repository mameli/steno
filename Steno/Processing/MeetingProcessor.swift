import Foundation
import StenoCore
import os

private let logger = Logger(subsystem: "dev.mameli.steno", category: "elaborazione")

/// L'Elaborazione delle Riunioni: una alla volta, in ordine d'arrivo, con lo stato salvato nella
/// cartella della Registrazione (`elaborazione.json`) così che riprenda dopo un riavvio o un crash.
/// Si occupa anche di Riprova, Rigenerazione, notifiche e conservazione dell'audio.
@MainActor
@Observable
final class MeetingProcessor {
    struct RecentMeeting: Identifiable {
        let id: UUID
        let title: String
        let status: ProcessingRecord.Status
        /// L'audio c'è ancora: si può Riprovare l'Elaborazione completa.
        let hasAudio: Bool
    }

    private let transcriber: LocalTranscriber
    /// Le Trascrizioni avviate durante la registrazione, da completare allo stop.
    private var liveTranscriptions: [UUID: MeetingTranscription] = [:]
    /// Copia in memoria dello stato delle Riunioni in registrazione: se il salvataggio su disco
    /// fallisce, allo stop la Riunione va comunque in coda.
    private var recordingRecords: [UUID: ProcessingRecord] = [:]
    /// L'ultima Elaborazione in coda: la prossima parte quando questa finisce.
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

    // MARK: - Ciclo di vita di una Riunione

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

    /// Dopo un riavvio: riprende le Elaborazioni rimaste a metà e recupera le Registrazioni
    /// interrotte da un crash, poi cancella l'audio scaduto.
    func resumeAfterLaunch() {
        let plan = ProcessingRecord.afterRestart(allRecords())
        plan.toSave.forEach(save)
        for var record in plan.toProcess {
            if record.status == .recording {
                do {
                    try recoverRecording(record, in: Self.directory(for: record.stenoID))
                } catch {
                    record.status = .failed(reason: "Registrazione interrotta e non recuperabile: \(error.localizedDescription)")
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

    // MARK: - Azioni dal menu Riunioni recenti

    func openNote(_ stenoID: UUID) {
        guard let vault = Vault.configured,
              let note = vault.findMeetingNote(stenoID: stenoID, expected: record(stenoID)?.noteURL)
        else {
            lastError = "Nota della Riunione non trovata nel Vault."
            return
        }
        Vault.openInObsidian(note)
    }

    /// Ripete l'Elaborazione completa (i segmenti già trascritti vengono dalla cache).
    /// Solo per Riunioni concluse: una in registrazione o già in coda non si tocca.
    func retry(_ stenoID: UUID) {
        guard var record = record(stenoID), (try? record.queueForRetry()) != nil else { return }
        save(record)
        enqueueProcessing(record)
    }

    /// Nuovo Riepilogo con un altro Template o Profilo, a partire dalla Trascrizione nel Vault:
    /// funziona anche dopo che l'audio è stato cancellato. Template e Profilo scelti all'avvio
    /// restano quelli della Riunione (li usa Riprova).
    func regenerate(_ stenoID: UUID, templateName: String? = nil, profile: ProviderProfile? = nil) {
        guard var record = record(stenoID), (try? record.beginRegeneration()) != nil else { return }
        save(record)
        enqueue { await self.runRegeneration(record, templateName: templateName, profile: profile) }
    }

    #if DEBUG
    /// Rielabora una Registrazione della cartella dati (prove automatiche) e aspetta la fine.
    func reprocess(_ directory: URL) async -> URL? {
        guard let recording = try? Recording.load(from: directory.appending(path: Recording.fileName)),
              Self.directory(for: recording.meetingID).standardizedFileURL == directory.standardizedFileURL
        else {
            lastError = "Rielaborazione rifiutata: la cartella non è nella cartella dati di Steno."
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

    // MARK: - Coda

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
        // Lo stato su disco può essere più recente (es. Template cambiato), altrimenti vale quello in coda.
        var record = record(queued.stenoID) ?? queued
        record.status = .processing
        save(record)
        let directory = Self.directory(for: record.stenoID)
        let transcription = liveTranscriptions.removeValue(forKey: record.stenoID)
            ?? MeetingTranscription(transcriber: transcriber, language: AppSettings.forcedLanguage)

        let recording: Recording
        do {
            recording = try Recording.load(from: directory.appending(path: Recording.fileName))
        } catch {
            finish(&record, problems: ["Registrazione illeggibile: \(error.localizedDescription)"], warnings: [])
            return
        }

        var problems: [String] = []
        // Un segmento illeggibile (es. quello aperto durante un crash) lascia un buco nella
        // Trascrizione ma non impedisce il Riepilogo: è un avviso, non un fallimento.
        var warnings: [String] = []
        let finished: MeetingTranscription.Finished?
        do {
            finished = try await transcription.finish(recording, in: directory)
            if let failedSegments = finished?.failedSegments, !failedSegments.isEmpty {
                warnings.append("Trascrizione incompleta: " + failedSegments.joined(separator: "; "))
            }
            lastTranscriptURL = finished?.url
        } catch {
            finished = nil
            problems.append("Trascrizione non riuscita: \(error.localizedDescription)")
        }

        if let vault = Vault.configured {
            do {
                let (noteURL, summaryProblem) = try await writeToVault(vault, finished, recording: recording, record: record)
                record.noteURL = noteURL
                lastNoteURL = noteURL
                if let summaryProblem { problems.append(summaryProblem) }
            } catch {
                problems.append("Scrittura nel Vault non riuscita: \(error.localizedDescription)")
            }
        } else {
            warnings.append("Nessun Vault configurato: niente Riepilogo, la Trascrizione è solo nella cartella della Registrazione.")
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
            finish(&record, problems: ["Rigenerazione non possibile: Nota della Riunione o Trascrizione non trovate nel Vault."], warnings: [])
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
            if case .failed(let reason) = summary { problems.append("Riepilogo non generato: \(reason)") }
            record.noteURL = noteURL
            lastNoteURL = noteURL
        } catch {
            problems.append("Rigenerazione non riuscita: \(error.localizedDescription)")
        }
        finish(&record, problems: problems, warnings: [])
    }

    private func finish(_ record: inout ProcessingRecord, problems: [String], warnings: [String]) {
        let noteName = record.noteURL?.deletingPathExtension().lastPathComponent ?? "Riunione"
        if problems.isEmpty {
            record.status = .completed
            lastError = warnings.isEmpty ? nil : warnings.joined(separator: " ")
            if Vault.configured == nil {
                Notifications.shared.notify(title: "Trascrizione pronta", body: "Configura il Vault per avere il Riepilogo.", note: nil)
            } else {
                let body = warnings.isEmpty ? noteName : "\(noteName) (\(warnings.joined(separator: " ")))"
                Notifications.shared.notify(title: "Riepilogo pronto", body: body, note: record.noteURL)
            }
        } else {
            let reason = problems.joined(separator: " ")
            record.status = .failed(reason: reason)
            lastError = reason
            logger.error("\(reason, privacy: .public)")
            Notifications.shared.notify(title: "Elaborazione non riuscita", body: "\(noteName): \(reason)", note: record.noteURL)
        }
        save(record)
    }

    // MARK: - Vault e Riepilogo

    /// Scrive l'esito dell'Elaborazione nel Vault: Riepilogo, titolo e rinomina, Trascrizione,
    /// Nota della Riunione. Restituisce la nota e, se c'è stato, il problema del Riepilogo.
    private func writeToVault(
        _ vault: Vault, _ finished: MeetingTranscription.Finished?, recording: Recording, record: ProcessingRecord
    ) async throws -> (URL, String?) {
        var noteURL = try vault.findMeetingNote(stenoID: record.stenoID, expected: record.noteURL)
            ?? vault.createMeetingNote(stenoID: record.stenoID, startedAt: record.startedAt)
        guard let finished else {
            try vault.update(noteURL) {
                $0.recordFailure(stenoID: record.stenoID, reason: "Trascrizione non riuscita: la Registrazione è salvata, si potrà riprovare.")
            }
            return (noteURL, nil)
        }

        let (summary, title) = await summarize(
            finished.transcript, language: finished.language,
            personalNotes: try vault.meetingNote(at: noteURL).personalNotes,
            template: vault.template(named: record.templateName), profile: record.summaryProfile,
            wantsTitle: true
        )
        // Si rinomina solo una nota ancora al suo posto e col nome provvisorio. Se la rinomina
        // fallisce la nota resta com'è: il Riepilogo non deve andare perso per un nome.
        if let title, vault.isInMeetingsFolder(noteURL),
           let newName = VaultNaming.renamedNoteName(
               current: noteURL.deletingPathExtension().lastPathComponent, startedAt: record.startedAt, title: title
           ) {
            do {
                noteURL = try vault.rename(noteURL, to: newName)
            } catch {
                logger.error("Rinomina della nota non riuscita: \(error, privacy: .public)")
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
                transcriptionProvider: "Locale",
                transcriptName: transcriptURL.deletingPathExtension().lastPathComponent,
                summary: summary
            )
        }
        if case .failed(let reason) = summary {
            return (noteURL, "Riepilogo non generato: \(reason)")
        }
        return (noteURL, nil)
    }

    /// Riepilogo e, se serve per la rinomina, titolo. Un titolo mancante non è un errore:
    /// la nota resta col nome provvisorio.
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
            return (.failed(reason: "nella Registrazione non c'è parlato."), nil)
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
            logger.error("Riepilogo non generato: \(error, privacy: .public)")
            return (.failed(reason: error.localizedDescription), nil)
        }
    }

    // MARK: - Stato su disco

    private func record(_ stenoID: UUID) -> ProcessingRecord? {
        try? ProcessingRecord.load(from: Self.directory(for: stenoID))
    }

    private func save(_ record: ProcessingRecord) {
        do {
            try record.save(in: Self.directory(for: record.stenoID))
        } catch {
            logger.error("Stato dell'Elaborazione non salvato: \(error, privacy: .public)")
            lastError = "Stato della Riunione non salvato su disco: un riavvio ora non la riprenderebbe. \(error.localizedDescription)"
        }
        refreshRecent()
    }

    private func allRecords() -> [ProcessingRecord] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: MeetingRecorder.meetingsDirectory, includingPropertiesForKeys: nil
        )) ?? []
        return folders.compactMap { try? ProcessingRecord.load(from: $0) }
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

    /// Ricostruisce `riunione.json` di una Registrazione interrotta da un crash dagli elenchi
    /// dei segmenti; la fine è l'ultima scrittura di un segmento.
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
            .save(to: directory.appending(path: Recording.fileName))
    }

    /// Cancella i file audio delle Registrazioni scadute, con le cache della trascrizione e la
    /// copia `trascrizione.md`. Restano `riunione.json` ed `elaborazione.json`: la Riunione resta
    /// tra le recenti e si può Rigenerare dalla Trascrizione nel Vault.
    func cleanUpExpiredRecordings() {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: MeetingRecorder.meetingsDirectory, includingPropertiesForKeys: nil
        )) ?? []
        let items = folders.compactMap { folder -> Retention.Item? in
            guard let stenoID = UUID(uuidString: folder.lastPathComponent) else { return nil }
            let record = try? ProcessingRecord.load(from: folder)
            let startedAt = record?.startedAt
                ?? (try? Recording.load(from: folder.appending(path: Recording.fileName)))?.startedAt
            guard let startedAt else { return nil }
            return Retention.Item(stenoID: stenoID, startedAt: startedAt, status: record?.status)
        }
        let kept: Set<String> = [Recording.fileName, ProcessingRecord.fileName]
        for stenoID in Retention.expired(items, now: Date(), days: AppSettings.retentionDays) {
            let folder = Self.directory(for: stenoID)
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where !kept.contains(file.lastPathComponent)
                && !Track.allCases.map(Segment.listFileName(for:)).contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        refreshRecent()
    }
}
