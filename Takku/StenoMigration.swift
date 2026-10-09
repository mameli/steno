import AppKit
import OSLog
import TakkuCore

private let logger = Logger(subsystem: "app.takku.takku", category: "migration")

/// Until 0.2.1 the app was called Steno (bundle `dev.mameli.steno`). Takku brings over Steno's
/// data folder, and at its first launch Steno's settings and API keys; the permissions must be granted
/// again, because macOS ties them to the bundle. Steno's notes in the Vault are read as they are
/// (see `MeetingNote`).
enum StenoMigration {
    private static let bundleID = "dev.mameli.steno"
    private static let doneKey = "migratedFromSteno"

    /// Runs before anything reads the settings or the data folder.
    static func runIfNeeded() {
        moveDataFolder()
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }
        guard let old = defaults.persistentDomain(forName: bundleID), !old.isEmpty else { return }

        // Keys already set by Takku win (e.g. a Debug build launched before the migration).
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        for profile in AppSettings.summaryProfiles {
            Keychain.copyAPIKey(for: profile.id, fromService: bundleID)
        }
        logger.info("Migrated Steno's settings")
    }

    /// Moves what is still in `Application Support/Steno` (Recordings and models) into
    /// `Application Support/Takku`, at every launch: Steno may have been opened again after the
    /// first migration. What Takku already has stays; Steno's folder goes once it is empty.
    private static func moveDataFolder() {
        let fileManager = FileManager.default
        let old = URL.applicationSupportDirectory.appending(path: "Steno", directoryHint: .isDirectory)
        let new = URL.applicationSupportDirectory.appending(path: "Takku", directoryHint: .isDirectory)
        // A running Steno may be writing a Recording.
        guard fileManager.fileExists(atPath: old.path(percentEncoded: false)),
              NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        else { return }

        let moved = merge(old, into: new)
        for item in moved {
            for file in [item] + ((fileManager.enumerator(at: item, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []) {
                switch file.lastPathComponent {
                case ".steno-downloaded":
                    // Otherwise the models would be downloaded again.
                    let marker = file.deletingLastPathComponent().appending(path: ".takku-downloaded")
                    if fileManager.fileExists(atPath: marker.path(percentEncoded: false)) {
                        try? fileManager.removeItem(at: file)
                    } else {
                        try? fileManager.moveItem(at: file, to: marker)
                    }
                case ProcessingRecord.fileName:
                    renameKey("stenoID", to: "takkuID", in: file)
                default:
                    break
                }
            }
        }
        if !containsFiles(old) { try? fileManager.removeItem(at: old) }
        if !moved.isEmpty { logger.info("Moved \(moved.count) items from Steno's data folder") }
    }

    /// Moves each item of `source` missing in `destination`, going into the folders both have.
    /// Returns the items moved, at their new place.
    private static func merge(_ source: URL, into destination: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        var moved: [URL] = []
        for item in items where item.lastPathComponent != ".DS_Store" {
            let target = destination.appending(path: item.lastPathComponent)
            if !fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
                do {
                    try fileManager.moveItem(at: item, to: target)
                    moved.append(target)
                } catch {
                    logger.error("\(item.lastPathComponent, privacy: .public) not moved from Steno's data folder: \(error.localizedDescription, privacy: .public)")
                }
            } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                moved += merge(item, into: target)
            }
        }
        return moved
    }

    /// Whether the folder still holds a file, `.DS_Store` aside.
    private static func containsFiles(_ folder: URL) -> Bool {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey])?.allObjects as? [URL] ?? []
        return files.contains {
            $0.lastPathComponent != ".DS_Store" && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
        }
    }

    private static func renameKey(_ old: String, to new: String, in file: URL) {
        guard let data = try? Data(contentsOf: file),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let value = object.removeValue(forKey: old)
        else { return }
        object[new] = value
        if let data = try? JSONSerialization.data(withJSONObject: object) {
            try? data.write(to: file, options: .atomic)
        }
    }
}
