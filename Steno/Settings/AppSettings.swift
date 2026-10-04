import Foundation
import StenoCore

/// Impostazioni di Steno, modificabili dalla finestra Impostazioni. Alcune solo da terminale, per esempio:
/// `defaults write dev.mameli.steno language it` (oppure `en`, `auto`)
/// `defaults write dev.mameli.steno echoCancellation -bool false`
enum AppSettings {
    private static let vaultPathKey = "vaultPath"
    private static let languageKey = "language"
    private static let echoCancellationKey = "echoCancellation"
    private static let openInObsidianKey = "openInObsidian"
    private static let summaryProfilesKey = "summaryProfiles"
    /// Usata anche da `@AppStorage` nel menu e nelle Impostazioni, che così restano allineati.
    static let activeProviderProfileKey = "activeProviderProfile"
    private static let defaultTemplateKey = "defaultTemplate"
    private static let retentionDaysKey = "retentionDays"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            echoCancellationKey: true,
            languageKey: "auto",
            openInObsidianKey: true,
            defaultTemplateKey: Template.defaultName,
            retentionDaysKey: Retention.days,
        ])
    }

    static var vaultPath: String? {
        get { UserDefaults.standard.string(forKey: vaultPathKey).flatMap { $0.isEmpty ? nil : $0 } }
        set { UserDefaults.standard.set(newValue, forKey: vaultPathKey) }
    }

    /// Giorni di conservazione dell'audio: `defaults write dev.mameli.steno retentionDays -int 14`.
    static var retentionDays: Int {
        max(1, UserDefaults.standard.integer(forKey: retentionDaysKey))
    }

    #if DEBUG
    /// Nelle prove automatiche ogni Riepilogo va al server finto, anche per Riunioni salvate con un altro Profilo.
    static var testSummaryProfile: ProviderProfile? {
        UserDefaults.standard.string(forKey: "testSummaryBaseURL").map {
            ProviderProfile(
                name: "Server di prova", baseURL: $0, model: "prova",
                maxContextTokens: ProviderProfile.defaultMaxContextTokens
            )
        }
    }
    #endif

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

    static var summaryProfiles: [ProviderProfile] {
        get {
            UserDefaults.standard.data(forKey: summaryProfilesKey)
                .flatMap { try? JSONDecoder().decode([ProviderProfile].self, from: $0) } ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: summaryProfilesKey) }
    }

    static var activeProviderProfileID: UUID? {
        get { UserDefaults.standard.string(forKey: activeProviderProfileKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: activeProviderProfileKey) }
    }

    static var activeProviderProfile: ProviderProfile? {
        #if DEBUG
        // Prove automatiche: `--args -testSummaryBaseURL http://localhost:8765/v1` usa un server finto
        // senza toccare i Profili dell'utente.
        if let testSummaryProfile { return testSummaryProfile }
        #endif
        return summaryProfiles.first { $0.id == activeProviderProfileID }
    }

    /// Nome (senza `.md`) del Template proposto all'avvio di ogni Riunione.
    static var defaultTemplate: String {
        get { UserDefaults.standard.string(forKey: defaultTemplateKey) ?? Template.defaultName }
        set { UserDefaults.standard.set(newValue, forKey: defaultTemplateKey) }
    }
}
