import Foundation

/// Impostazioni di Steno. Finché non c'è una finestra apposita si cambiano da terminale, per esempio:
/// `defaults write dev.mameli.steno vaultPath ~/Documents/Vault`
/// `defaults write dev.mameli.steno language it` (oppure `en`, `auto`)
/// `defaults write dev.mameli.steno echoCancellation -bool false`
enum Settings {
    private static let vaultPathKey = "vaultPath"
    private static let languageKey = "language"
    private static let echoCancellationKey = "echoCancellation"
    private static let openInObsidianKey = "openInObsidian"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            echoCancellationKey: true,
            languageKey: "auto",
            openInObsidianKey: true,
        ])
    }

    static var vaultPath: String? {
        UserDefaults.standard.string(forKey: vaultPathKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `nil` per rilevare la lingua in automatico.
    static var forcedLanguage: String? {
        UserDefaults.standard.string(forKey: languageKey).flatMap {
            LocalTranscriber.supportedLanguages.contains($0) ? $0 : nil
        }
    }

    static var echoCancellation: Bool {
        UserDefaults.standard.bool(forKey: echoCancellationKey)
    }

    /// Spento solo nelle prove automatiche, che scrivono in un Vault di test sconosciuto a Obsidian.
    static var openInObsidian: Bool {
        UserDefaults.standard.bool(forKey: openInObsidianKey)
    }
}
