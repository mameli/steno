import AppKit
import StenoCore

/// The Obsidian Vault where Steno writes Meeting notes and Transcripts.
struct Vault {
    let root: URL

    var meetingsFolder: URL { root.appending(path: "Meetings", directoryHint: .isDirectory) }
    var transcriptsFolder: URL { meetingsFolder.appending(path: "Transcripts", directoryHint: .isDirectory) }
    var templatesFolder: URL { meetingsFolder.appending(path: "_Templates", directoryHint: .isDirectory) }

    static var configured: Vault? {
        AppSettings.vaultPath.map { Vault(root: URL(filePath: $0, directoryHint: .isDirectory)) }
    }

    // MARK: - Templates

    /// The available Templates, by file name (without `.md`), in alphabetical order.
    func templateNames() -> [String] {
        Self.noteNames(in: templatesFolder).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The Templates to offer in a menu: the Vault's plus the one already chosen, even if it is gone meanwhile.
    static func templateChoices(including selected: String) -> [String] {
        let names = configured?.templateNames() ?? []
        return names.contains(selected) ? names : [selected] + names
    }

    /// Creates the default Template (Notes) if the Templates folder has none, or if the
    /// default Template of the Settings no longer exists (then the default becomes Notes).
    func ensureDefaultTemplate() throws {
        let names = templateNames()
        guard names.isEmpty || !names.contains(AppSettings.defaultTemplate) else { return }
        try FileManager.default.createDirectory(at: templatesFolder, withIntermediateDirectories: true)
        if !names.contains(Template.defaultName) {
            try Template.defaultFileContent.write(to: templateURL(Template.defaultName), atomically: true, encoding: .utf8)
        }
        AppSettings.defaultTemplate = Template.defaultName
    }

    /// Creates a new Template from the default one and returns its file name (without `.md`).
    func createTemplate(named name: String) throws -> String {
        guard let safeName = VaultNaming.fileName(name) else { throw VaultError.invalidName(name) }
        try FileManager.default.createDirectory(at: templatesFolder, withIntermediateDirectories: true)
        let fileName = VaultNaming.available(safeName, taken: Self.noteNames(in: templatesFolder))
        try Template.newFileContent(name: fileName)
            .write(to: templateURL(fileName), atomically: true, encoding: .utf8)
        return fileName
    }

    /// Moves the Template to the Trash: it can be recovered.
    func trashTemplate(named name: String) throws {
        try FileManager.default.trashItem(at: templateURL(name), resultingItemURL: nil)
    }

    func templateURL(_ name: String) -> URL {
        templatesFolder.appending(path: name + ".md")
    }

    /// The Template with that file name; if it is gone, the default one.
    func template(named name: String) -> Template {
        guard let content = try? String(contentsOf: templateURL(name), encoding: .utf8) else {
            return Template(fileName: Template.defaultName, content: Template.defaultFileContent)
        }
        return Template(fileName: name, content: content)
    }

    // MARK: - Meeting notes and Transcripts

    /// Creates the Meeting note with the provisional title. Never creates the Vault folder:
    /// if it is missing (volume not mounted) it fails, and the note is created at the end of Processing.
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

    /// The Meeting note: at the known path or, if the user renamed or moved it, by looking
    /// for its `steno_id` in the Meetings folder (Transcripts excluded).
    func findMeetingNote(stenoID: UUID, expected: URL?) -> URL? {
        if let expected, Self.belongs(expected, to: stenoID) { return expected }
        return Self.firstFile(in: meetingsFolder, excluding: transcriptsFolder) { Self.belongs($0, to: stenoID) }
    }

    /// The Transcript file of a Meeting, found by its `steno_id`.
    func findTranscript(stenoID: UUID) -> URL? {
        Self.firstFile(in: transcriptsFolder) { Self.belongs($0, to: stenoID) }
    }

    /// Writes the Transcript in the Vault. If a file of the same Meeting already exists it is
    /// overwritten, so a new Processing does not create duplicates.
    func writeTranscript(_ transcript: Transcript, stenoID: UUID, meetingNoteName: String, language: String?) throws -> URL {
        try FileManager.default.createDirectory(at: transcriptsFolder, withIntermediateDirectories: true)
        let url = findTranscript(stenoID: stenoID) ?? {
            let name = VaultNaming.available("\(meetingNoteName) (transcript)", taken: Self.noteNames(in: transcriptsFolder))
            return transcriptsFolder.appending(path: name + ".md")
        }()
        let content = transcript.vaultFile(stenoID: stenoID, meetingNoteName: meetingNoteName, language: language)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// The note is still in the Meetings folder, where Steno created it (it was not moved).
    func isInMeetingsFolder(_ noteURL: URL) -> Bool {
        noteURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            == meetingsFolder.resolvingSymlinksInPath().standardizedFileURL
    }

    /// Renames the note (with a " (2)" suffix if the name is taken) and returns the new path.
    func rename(_ noteURL: URL, to name: String) throws -> URL {
        let folder = noteURL.deletingLastPathComponent()
        let current = noteURL.deletingPathExtension().lastPathComponent
        let available = VaultNaming.available(name, taken: Self.noteNames(in: folder).subtracting([current]))
        let destination = folder.appending(path: available + ".md")
        guard destination != noteURL else { return noteURL }
        try FileManager.default.moveItem(at: noteURL, to: destination)
        return destination
    }

    func meetingNote(at url: URL) throws -> MeetingNote {
        MeetingNote(content: try String(contentsOf: url, encoding: .utf8))
    }

    /// Edits an existing note. If Obsidian saves it between the read and the write, it is read
    /// again and the change reapplied, so what the user just typed is not lost.
    /// The write happens on the file itself (not replacing it): symlinks and creation date survive.
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

    // MARK: - Private

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
    case invalidName(String)

    var errorDescription: String? {
        switch self {
        case .unreachable(let path): String(localized: "Vault not reachable: \(path).")
        case .busy(let file): String(localized: "\(file) keeps changing while Steno tries to update it.")
        case .invalidName(let name): String(localized: "\"\(name)\" is not a valid file name.")
        }
    }
}
