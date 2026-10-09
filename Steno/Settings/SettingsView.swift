import AppKit
import StenoCore
import SwiftUI

/// Settings window: General (start at login, calendar, call suggestions, updates), Vault, Templates,
/// Vocabulary, Recordings, Meeting languages and transcription models, Provider Profiles for the Summary.
struct SettingsView: View {
    let models: TranscriptionModels
    @State private var vaultPath = AppSettings.vaultPath ?? ""
    @State private var profiles = AppSettings.summaryProfiles
    @AppStorage(AppSettings.activeProviderProfileKey) private var activeProfileID = ""
    @State private var selectedProfileID = AppSettings.activeProviderProfile?.id ?? AppSettings.summaryProfiles.first?.id
    @State private var defaultTemplate = AppSettings.defaultTemplate

    var body: some View {
        Form {
            Section {
                LaunchAtLoginToggle()
                CalendarToggle()
                SuggestCallsToggle()
                UpdatesToggle()
            } header: {
                // The header of the first Section, so the icon scrolls away with the rest.
                VStack(alignment: .leading, spacing: 16) {
                    AppIdentity().frame(maxWidth: .infinity)
                    Text("General")
                }
            }

            Section("Obsidian Vault") {
                LabeledContent("Folder") {
                    HStack {
                        Text(vaultPath.isEmpty ? String(localized: "None") : vaultPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(vaultPath.isEmpty ? .secondary : .primary)
                        Button("Choose…", action: chooseVault)
                    }
                }
            }

            TemplatesSection(defaultTemplate: $defaultTemplate, vaultPath: vaultPath)

            VocabularySection(vaultPath: vaultPath)

            RecordingsSection()

            TranscriptionSection(models: models)

            Section {
                if profiles.isEmpty {
                    Text("No Profile yet. Add one to generate Summaries.")
                        .foregroundStyle(.secondary)
                }
                ForEach(profiles) { profile in
                    ProfileRow(
                        profile: profile,
                        isActive: profile.id.uuidString == activeProfileID,
                        isSelected: profile.id == selectedProfileID
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedProfileID = profile.id }
                }
                HStack {
                    Button("Add Profile", action: addProfile)
                    Spacer()
                    Button("Delete", role: .destructive, action: deleteSelectedProfile)
                        .disabled(selectedProfileID == nil)
                }
            } header: {
                Text("Summary Profiles")
            } footer: {
                Text("Any server with an OpenAI-compatible API. For work meetings use only local Providers or Providers based and hosting data in the EU.")
                    .foregroundStyle(.secondary)
            }

            if let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) {
                ProfileEditor(
                    profile: $profiles[index],
                    isActive: profiles[index].id.uuidString == activeProfileID,
                    activate: { activeProfileID = profiles[index].id.uuidString }
                )
                .id(profiles[index].id)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 600)
        .onChange(of: profiles) { AppSettings.summaryProfiles = profiles }
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Use this Vault")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        vaultPath = url.path(percentEncoded: false)
        AppSettings.vaultPath = vaultPath
        try? Vault.configured?.ensureDefaultTemplate()
    }

    private func addProfile() {
        let profile = ProviderProfile(
            name: "", baseURL: "", model: "", maxContextTokens: ProviderProfile.defaultMaxContextTokens
        )
        // Not made active: an empty Profile would make every Meeting fail until it is filled in.
        // The user activates it with "Use for Summaries" once it works.
        profiles.append(profile)
        selectedProfileID = profile.id
    }

    private func deleteSelectedProfile() {
        guard let id = selectedProfileID else { return }
        Keychain.deleteAPIKey(for: id)
        profiles.removeAll { $0.id == id }
        if activeProfileID == id.uuidString { activeProfileID = "" }
        selectedProfileID = profiles.first?.id
    }
}
