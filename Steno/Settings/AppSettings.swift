import Foundation
import StenoCore

/// Steno's settings, editable in the Settings window. Some only from the terminal, for example:
/// `defaults write dev.mameli.steno language it` (or `en`, `auto`)
/// `defaults write dev.mameli.steno echoCancellation -bool false`
enum AppSettings {
    private static let vaultPathKey = "vaultPath"
    private static let languageKey = "language"
    private static let echoCancellationKey = "echoCancellation"
    private static let openInObsidianKey = "openInObsidian"
    private static let summaryProfilesKey = "summaryProfiles"
    private static let defaultTemplateKey = "defaultTemplate"
    private static let retentionDaysKey = "retentionDays"
    /// Also used by `@AppStorage` in the menu and in Settings, so the two stay in sync.
    static let activeProviderProfileKey = "activeProviderProfile"

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

    /// Days the audio is kept: `defaults write dev.mameli.steno retentionDays -int 14`.
    static var retentionDays: Int {
        max(1, UserDefaults.standard.integer(forKey: retentionDaysKey))
    }

    #if DEBUG
    /// In automated tests every Summary goes to the fake server, even for Meetings saved with another Profile.
    static var testSummaryProfile: ProviderProfile? {
        UserDefaults.standard.string(forKey: "testSummaryBaseURL").map {
            ProviderProfile(
                name: "Test server", baseURL: $0, model: "test",
                maxContextTokens: ProviderProfile.defaultMaxContextTokens
            )
        }
    }
    #endif

    /// `nil` to detect the language automatically.
    static var forcedLanguage: String? {
        UserDefaults.standard.string(forKey: languageKey).flatMap {
            LocalTranscriber.supportedLanguages.contains($0) ? $0 : nil
        }
    }

    static var echoCancellation: Bool {
        UserDefaults.standard.bool(forKey: echoCancellationKey)
    }

    /// Off only in automated tests, which write to a test Vault Obsidian does not know.
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
        // Automated tests: `--args -testSummaryBaseURL http://localhost:8765/v1` uses a fake server
        // without touching the user's Profiles.
        if let testSummaryProfile { return testSummaryProfile }
        #endif
        return summaryProfiles.first { $0.id == activeProviderProfileID }
    }

    /// Name (without `.md`) of the Template proposed when every Meeting starts.
    static var defaultTemplate: String {
        get { UserDefaults.standard.string(forKey: defaultTemplateKey) ?? Template.defaultName }
        set { UserDefaults.standard.set(newValue, forKey: defaultTemplateKey) }
    }
}
