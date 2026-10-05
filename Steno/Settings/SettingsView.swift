import AppKit
import StenoCore
import SwiftUI

/// Minimal Settings window: Vault, Templates, Provider Profiles for the Summary.
struct SettingsView: View {
    @State private var vaultPath = AppSettings.vaultPath ?? ""
    @State private var profiles = AppSettings.summaryProfiles
    @AppStorage(AppSettings.activeProviderProfileKey) private var activeProfileID = ""
    @State private var selectedProfileID = AppSettings.activeProviderProfile?.id ?? AppSettings.summaryProfiles.first?.id
    @State private var defaultTemplate = AppSettings.defaultTemplate

    var body: some View {
        Form {
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
        profiles.append(profile)
        selectedProfileID = profile.id
        if activeProfileID.isEmpty { activeProfileID = profile.id.uuidString }
    }

    private func deleteSelectedProfile() {
        guard let id = selectedProfileID else { return }
        Keychain.deleteAPIKey(for: id)
        profiles.removeAll { $0.id == id }
        if activeProfileID == id.uuidString { activeProfileID = "" }
        selectedProfileID = profiles.first?.id
    }
}

/// The Vault's Templates: created here and written in Obsidian, like the other notes.
private struct TemplatesSection: View {
    @Binding var defaultTemplate: String
    /// Changes when another Vault is chosen: the list must be read again.
    let vaultPath: String
    @State private var names: [String] = []
    @State private var newName = ""
    @State private var status: String?
    @State private var pendingDeletion: String?

    var body: some View {
        Section {
            if Vault.configured == nil {
                Text("Choose the Vault first.").foregroundStyle(.secondary)
            } else {
                Picker("Default Template", selection: $defaultTemplate) {
                    ForEach(Vault.templateChoices(including: defaultTemplate), id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: defaultTemplate) { AppSettings.defaultTemplate = defaultTemplate }

                ForEach(names, id: \.self) { name in
                    HStack {
                        Text(name)
                        if name == defaultTemplate {
                            Text("Default").font(.caption).foregroundStyle(.green)
                        }
                        Spacer()
                        Button("Open in Obsidian") { open(name) }
                        // Notes cannot go: Steno would create it again as the fallback Template.
                        if name != Template.defaultName {
                            Button("Delete", role: .destructive) { pendingDeletion = name }
                        }
                    }
                }

                LabeledContent("New Template") {
                    HStack {
                        PasteableTextField(placeholder: String(localized: "e.g. Weekly 1:1"), text: $newName)
                        Button("Create and open", action: create)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let status {
                    Text(status).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Templates")
        } footer: {
            Text("A new Template starts from Notes: change instructions and sections in Obsidian. They live in Meetings/_Templates/ in the Vault.")
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: reload)
        .onChange(of: vaultPath) { reload() }
        .confirmationDialog(
            String(localized: "Move the Template \"\(pendingDeletion ?? "")\" to the Trash?"),
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
        ) {
            Button("Move to Trash", role: .destructive) {
                if let name = pendingDeletion { delete(name) }
            }
        } message: {
            Text("Meetings that used it switch to the Notes Template.")
        }
    }

    private func reload() {
        names = Vault.configured?.templateNames() ?? []
    }

    private func create() {
        guard let vault = Vault.configured else { return }
        do {
            let name = try vault.createTemplate(named: newName)
            newName = ""
            reload()
            status = String(localized: "Created \"\(name)\": edit it in Obsidian.")
            Vault.openNewFileInObsidian(vault.templateURL(name))
        } catch {
            status = error.localizedDescription
        }
    }

    private func open(_ name: String) {
        guard let vault = Vault.configured else { return }
        Vault.openInObsidian(vault.templateURL(name))
    }

    private func delete(_ name: String) {
        guard let vault = Vault.configured else { return }
        do {
            try vault.trashTemplate(named: name)
            if defaultTemplate == name { defaultTemplate = Template.defaultName }
            try? vault.ensureDefaultTemplate()
            reload()
            // The row disappearing is enough: no message, and none left over from before.
            status = nil
        } catch {
            status = error.localizedDescription
        }
        pendingDeletion = nil
    }
}

private struct ProfileRow: View {
    let profile: ProviderProfile
    let isActive: Bool
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "pencil.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            VStack(alignment: .leading) {
                Text(profile.displayName)
                Text(profile.model.isEmpty ? String(localized: "To be configured") : profile.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Text("In use").font(.caption).foregroundStyle(.green)
            }
        }
    }
}

private struct ProfileEditor: View {
    @Binding var profile: ProviderProfile
    let isActive: Bool
    let activate: () -> Void
    @State private var apiKey = ""
    /// Last characters of the saved key, so the user can tell which key is stored; `nil` if none.
    @State private var storedKeySuffix: String?
    @State private var status: String?
    @State private var isTesting = false

    var body: some View {
        Section {
            LabeledContent("Name") {
                PasteableTextField(placeholder: String(localized: "e.g. Mistral EU"), text: $profile.name)
            }
            LabeledContent("Base URL") {
                PasteableTextField(placeholder: String(localized: "e.g. https://api.mistral.ai/v1"), text: $profile.baseURL)
            }
            LabeledContent("Model") {
                PasteableTextField(placeholder: String(localized: "e.g. mistral-medium-latest"), text: $profile.model)
            }
            TextField("Max context (tokens)", value: $profile.maxContextTokens, format: .number)

            // The only place where the key is entered. It is saved only on Return or with the
            // button, never while typing: a stray keystroke must not replace a working key.
            LabeledContent("API key") {
                HStack {
                    PasteableTextField(
                        placeholder: storedKeySuffix.map { String(localized: "Saved in the Keychain (…\($0)) · paste here to replace it") }
                            ?? String(localized: "Paste the key here"),
                        text: $apiKey,
                        isSecure: true,
                        onSubmit: saveKey
                    )
                    if !apiKey.isEmpty {
                        Button("Save key", action: saveKey)
                    } else if storedKeySuffix != nil {
                        Button("Remove", role: .destructive) {
                            Keychain.deleteAPIKey(for: profile.id)
                            storedKeySuffix = nil
                            status = String(localized: "Key removed.")
                        }
                    }
                }
            }

            HStack {
                Button("Test connection") { Task { await test() } }
                    .disabled(isTesting || profile.baseURL.isEmpty || profile.model.isEmpty)
                if isTesting { ProgressView().controlSize(.small) }
                Spacer()
                if isActive {
                    Text("Used for Summaries").foregroundStyle(.green)
                } else {
                    Button("Use for Summaries", action: activate)
                }
            }
            if let status {
                Text(status).foregroundStyle(.secondary).textSelection(.enabled)
            }
        } header: {
            Text("Profile: \(profile.displayName)")
        } footer: {
            Text("Changes are saved as you type. The key goes to the Keychain when you press Return or Save key.")
                .foregroundStyle(.secondary)
        }
        .onAppear { refreshStoredKey() }
    }

    private func saveKey() {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try Keychain.setAPIKey(apiKey, for: profile.id)
            apiKey = ""
            refreshStoredKey()
            status = String(localized: "Key saved in the Keychain.")
        } catch {
            status = error.localizedDescription
        }
    }

    private func refreshStoredKey() {
        storedKeySuffix = Keychain.apiKey(for: profile.id).map { String($0.suffix(4)) }
    }

    private func test() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let reply = try await ChatClient(profile: profile).complete([
                ChatMessage(role: .user, content: "Reply with the word OK only."),
            ])
            status = String(localized: "It works. Reply: \(String(reply.prefix(40)))")
        } catch {
            status = error.localizedDescription
        }
    }
}
