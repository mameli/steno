import Foundation

/// Moves the data folders of versions before the English rewrite: `Steno/Riunioni` →
/// `Steno/Recordings` and `Steno/Modelli` → `Steno/Models` (so the 646 MB model is not
/// downloaded again). Never overwrites an existing folder.
enum StorageMigration {
    static func run() {
        let base = URL.applicationSupportDirectory.appending(path: "Steno", directoryHint: .isDirectory)
        for (legacy, current) in [("Riunioni", "Recordings"), ("Modelli", "Models")] {
            let from = base.appending(path: legacy, directoryHint: .isDirectory)
            let to = base.appending(path: current, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: from.path(percentEncoded: false)),
                  !FileManager.default.fileExists(atPath: to.path(percentEncoded: false))
            else { continue }
            try? FileManager.default.moveItem(at: from, to: to)
        }
    }
}
