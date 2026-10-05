import AppKit
import ServiceManagement
import StenoCore
import SwiftUI

/// Minimal Settings window: start at login, Vault, Templates, Recordings, transcription models,
/// Provider Profiles for the Summary.
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

/// Icon, name and version at the top of Settings.
private struct AppIdentity: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 4) {
            // From the asset catalog: the icon macOS caches for the app can be an old one.
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text(verbatim: "Steno").font(.title2.bold()).foregroundStyle(.primary)
            Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

/// Starts Steno when the user logs in, as a login item registered with macOS: it also appears,
/// and can be turned off, in System Settings → General → Login Items.
private struct LaunchAtLoginToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var error: String?

    var body: some View {
        Toggle("Open at login", isOn: Binding(
            get: { status == .enabled || status == .requiresApproval },
            set: setEnabled
        ))
        // The status can change in System Settings while this window is closed.
        .onAppear { status = SMAppService.mainApp.status }
        if status == .requiresApproval {
            HStack {
                Text("Allow Steno in System Settings → Login Items.").foregroundStyle(.secondary)
                Spacer()
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        if let error {
            Text(error).foregroundStyle(.secondary)
        }
    }

    private func setEnabled(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        status = SMAppService.mainApp.status
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

/// The Whisper models: download, choose the one in use, delete the others.
private struct TranscriptionSection: View {
    let models: TranscriptionModels
    @AppStorage(AppSettings.transcriptionModelKey) private var selectedID = TranscriptionModel.default.id
    @State private var error: String?

    var body: some View {
        Section {
            ForEach(TranscriptionModel.all) { model in
                row(model)
            }
            if let error {
                Text(error).foregroundStyle(.secondary).textSelection(.enabled)
            }
        } header: {
            Text("Transcription")
        } footer: {
            Text("Models run on this Mac. Each is downloaded once from Hugging Face: only the model is downloaded, no audio or text is sent. The model in use applies to new Meetings and to Retry.")
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ model: TranscriptionModel) -> some View {
        // Read through `selectedID`, so the rows follow a change made in the menu.
        let isSelected = model.id == (TranscriptionModel.all.first { $0.id == selectedID } ?? .default).id
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: model.name)
                    if isSelected {
                        Text("In use").font(.caption).foregroundStyle(.green)
                    }
                }
                HStack(spacing: 4) {
                    Text(model.note)
                    Text(verbatim: "·")
                    Text((Int64(model.downloadMB) * 1_000_000).formatted(.byteCount(style: .file)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let percent = models.progress[model.id] {
                if percent < 100 {
                    ProgressView(value: Double(percent), total: 100).frame(width: 80)
                    Text(verbatim: "\(percent)%").monospacedDigit().frame(width: 40, alignment: .trailing)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Preparing…").foregroundStyle(.secondary)
                }
            } else if models.isDownloaded(model) {
                if !isSelected {
                    Button("Use") { selectedID = model.id }
                    // The model in use is not deleted: the next Meeting would download it again.
                    Button("Delete", role: .destructive) { delete(model) }
                }
            } else {
                Button("Download") { download(model) }
            }
        }
    }

    private func download(_ model: TranscriptionModel) {
        error = nil
        Task {
            do {
                try await models.download(model)
            } catch {
                self.error = String(localized: "Download of \(model.name) failed: \(error.localizedDescription)")
            }
        }
    }

    private func delete(_ model: TranscriptionModel) {
        do {
            try models.delete(model)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The audio kept on this Mac: how long, how much, where, and deleting it ahead of time.
private struct RecordingsSection: View {
    @State private var days = AppSettings.retentionDays
    @State private var size: Int64 = 0
    @State private var isConfirmingDeletion = false

    var body: some View {
        Section {
            Stepper(value: $days, in: 1...90) {
                Text("Keep audio for \(days) days")
            }
            // Applied by the cleanup at launch and once a day: a click too many on the Stepper
            // must not delete audio on the spot.
            .onChange(of: days) { AppSettings.retentionDays = days }
            LabeledContent("Audio on this Mac") {
                HStack {
                    Text(size.formatted(.byteCount(style: .file)))
                    Button("Show in Finder", action: showInFinder)
                    Button("Delete audio", role: .destructive) { isConfirmingDeletion = true }
                        .disabled(size == 0)
                }
            }
        } header: {
            Text("Recordings")
        } footer: {
            Text("About 20 MB per hour of Meeting. Notes and Transcripts stay in the Vault: without the audio, Retry makes only the Summary again.")
                .foregroundStyle(.secondary)
        }
        .onAppear { size = MeetingProcessor.audioSize() }
        .confirmationDialog(
            String(localized: "Delete the audio of all concluded Meetings?"),
            isPresented: $isConfirmingDeletion
        ) {
            Button("Delete audio", role: .destructive) {
                MeetingProcessor.deleteAudio(olderThanDays: 0)
                size = MeetingProcessor.audioSize()
            }
        } message: {
            Text("It cannot be undone. Meetings being recorded or processed are not touched.")
        }
    }

    private func showInFinder() {
        let folder = MeetingRecorder.recordingsDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
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
