import AppKit
import StenoCore

/// Il Vault Obsidian in cui Steno scrive le Note della Riunione e le Trascrizioni.
struct Vault {
    let root: URL

    var meetingsFolder: URL { root.appending(path: "Meetings", directoryHint: .isDirectory) }
    var transcriptsFolder: URL { meetingsFolder.appending(path: "Trascrizioni", directoryHint: .isDirectory) }

    static var configured: Vault? {
        Settings.vaultPath.map { Vault(root: URL(filePath: $0, directoryHint: .isDirectory)) }
    }

    /// Crea la Nota della Riunione con il titolo provvisorio. Non crea mai la cartella del Vault:
    /// se non c'è (volume non montato) fallisce, e la nota verrà creata a fine Elaborazione.
    func createMeetingNote(stenoID: UUID, startedAt: Date) throws -> URL {
        guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else {
            throw VaultError.unreachable(root.path(percentEncoded: false))
        }
        try FileManager.default.createDirectory(at: meetingsFolder, withIntermediateDirectories: true)
        let name = VaultNaming.available(
            VaultNaming.noteName(startedAt: startedAt, title: VaultNaming.defaultTitle),
            taken: Self.noteNames(in: meetingsFolder)
        )
        let url = meetingsFolder.appending(path: name + ".md")
        let note = MeetingNote.initial(stenoID: stenoID, startedAt: startedAt)
        try note.content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// La Nota della Riunione: al percorso noto o, se l'utente l'ha rinominata o spostata,
    /// cercando il suo `steno_id` nella cartella Meetings (Trascrizioni escluse).
    func findMeetingNote(stenoID: UUID, expected: URL?) -> URL? {
        if let expected, Self.belongs(expected, to: stenoID) { return expected }
        return Self.firstFile(in: meetingsFolder, excluding: transcriptsFolder) { Self.belongs($0, to: stenoID) }
    }

    /// Scrive la Trascrizione nel Vault. Se esiste già un file della stessa Riunione lo
    /// sovrascrive, così una nuova Elaborazione non crea doppioni.
    func writeTranscript(_ transcript: Transcript, stenoID: UUID, meetingNoteName: String, language: String?) throws -> URL {
        try FileManager.default.createDirectory(at: transcriptsFolder, withIntermediateDirectories: true)
        let url = Self.firstFile(in: transcriptsFolder) { Self.belongs($0, to: stenoID) } ?? {
            let name = VaultNaming.available("\(meetingNoteName) (trascrizione)", taken: Self.noteNames(in: transcriptsFolder))
            return transcriptsFolder.appending(path: name + ".md")
        }()
        let content = transcript.vaultFile(stenoID: stenoID, meetingNoteName: meetingNoteName, language: language)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Modifica una nota esistente. Se Obsidian la salva tra la lettura e la scrittura,
    /// la rilegge e riapplica la modifica, così non si perde quello che l'utente ha appena scritto.
    /// La scrittura avviene sul file stesso (non lo sostituisce): restano link simbolici e data di creazione.
    func update(_ noteURL: URL, _ change: (inout MeetingNote) -> Void) throws {
        for _ in 0..<3 {
            let before = try Self.modificationDate(noteURL)
            var note = MeetingNote(content: try String(contentsOf: noteURL, encoding: .utf8))
            change(&note)
            guard try Self.modificationDate(noteURL) == before else { continue }
            try note.content.write(to: noteURL, atomically: false, encoding: .utf8)
            return
        }
        throw VaultError.busy(noteURL.lastPathComponent)
    }

    static func openInObsidian(_ url: URL) {
        var components = URLComponents(string: "obsidian://open")!
        components.queryItems = [URLQueryItem(name: "path", value: url.path(percentEncoded: false))]
        NSWorkspace.shared.open(components.url!)
    }

    private static func belongs(_ url: URL, to stenoID: UUID) -> Bool {
        (try? String(contentsOf: url, encoding: .utf8)).map { MeetingNote(content: $0).stenoID == stenoID } ?? false
    }

    private static func firstFile(in folder: URL, excluding excluded: URL? = nil, where matches: (URL) -> Bool) -> URL? {
        let excludedComponents = excluded.map { $0.resolvingSymlinksInPath().standardizedFileURL.pathComponents }
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            let components = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            if let excludedComponents, components.starts(with: excludedComponents) { continue }
            if matches(url) { return url }
        }
        return nil
    }

    private static func noteNames(in folder: URL) -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return Set(files.filter { $0.pathExtension == "md" }.map { $0.deletingPathExtension().lastPathComponent })
    }

    private static func modificationDate(_ url: URL) throws -> Date? {
        try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.modificationDate] as? Date
    }
}

enum VaultError: LocalizedError {
    case unreachable(String)
    case busy(String)

    var errorDescription: String? {
        switch self {
        case .unreachable(let path): "Vault non raggiungibile: \(path)."
        case .busy(let file): "\(file) continua a cambiare mentre Steno prova ad aggiornarla."
        }
    }
}
