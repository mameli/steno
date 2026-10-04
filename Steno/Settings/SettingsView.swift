import AppKit
import StenoCore
import SwiftUI

/// Finestra Impostazioni essenziale: Vault, Profili per il Riepilogo, Template di default.
struct SettingsView: View {
    @State private var vaultPath = AppSettings.vaultPath ?? ""
    @State private var profiles = AppSettings.summaryProfiles
    @AppStorage(AppSettings.activeProviderProfileKey) private var activeProfileID = ""
    @State private var selectedProfileID = AppSettings.activeProviderProfileID ?? AppSettings.summaryProfiles.first?.id
    @State private var defaultTemplate = AppSettings.defaultTemplate

    var body: some View {
        Form {
            Section("Vault Obsidian") {
                LabeledContent("Cartella") {
                    HStack {
                        Text(vaultPath.isEmpty ? "Nessuna" : vaultPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(vaultPath.isEmpty ? .secondary : .primary)
                        Button("Scegli…", action: chooseVault)
                    }
                }
                Picker("Template di default", selection: $defaultTemplate) {
                    ForEach(Vault.templateChoices(including: defaultTemplate), id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: defaultTemplate) { AppSettings.defaultTemplate = defaultTemplate }
            }

            Section {
                Picker("Profilo attivo", selection: $activeProfileID) {
                    Text("Nessuno").tag("")
                    ForEach(profiles) { Text($0.displayName).tag($0.id.uuidString) }
                }

                Picker("Modifica", selection: $selectedProfileID) {
                    ForEach(profiles) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                .disabled(profiles.isEmpty)

                if let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) {
                    ProfileEditor(profile: $profiles[index])
                        .id(profiles[index].id)
                }

                HStack {
                    Button("Aggiungi Profilo", action: addProfile)
                    Button("Elimina Profilo", role: .destructive, action: deleteSelectedProfile)
                        .disabled(selectedProfileID == nil)
                }
            } header: {
                Text("Profili per il Riepilogo")
            } footer: {
                Text("Qualsiasi server con API compatibile OpenAI. Per le riunioni di lavoro usa solo Provider locali o con sede e dati in UE.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 520)
        .onChange(of: profiles) { AppSettings.summaryProfiles = profiles }
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Usa questo Vault"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        vaultPath = url.path(percentEncoded: false)
        AppSettings.vaultPath = vaultPath
        try? Vault.configured?.ensureDefaultTemplate()
    }

    private func addProfile() {
        let profile = ProviderProfile(
            name: "Nuovo Profilo", baseURL: "", model: "", maxContextTokens: ProviderProfile.defaultMaxContextTokens
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

private struct ProfileEditor: View {
    @Binding var profile: ProviderProfile
    @State private var apiKey = ""
    @State private var hasStoredKey = false
    @State private var status: String?
    @State private var isTesting = false

    var body: some View {
        TextField("Nome", text: $profile.name)
        TextField("URL base", text: $profile.baseURL, prompt: Text("https://api.mistral.ai/v1"))
        TextField("Modello", text: $profile.model, prompt: Text("mistral-medium-latest"))
        TextField("Contesto massimo (token)", value: $profile.maxContextTokens, format: .number)
        LabeledContent("Chiave API") {
            HStack {
                SecureField(hasStoredKey ? "Salvata nel Portachiavi" : "Nessuna (server locale)", text: $apiKey)
                Button("Salva") { saveKey() }
                    .disabled(apiKey.isEmpty)
                if hasStoredKey {
                    Button("Rimuovi") {
                        Keychain.deleteAPIKey(for: profile.id)
                        hasStoredKey = false
                    }
                }
            }
        }
        HStack {
            Button("Prova connessione") { Task { await test() } }
                .disabled(isTesting || profile.baseURL.isEmpty || profile.model.isEmpty)
            if isTesting { ProgressView().controlSize(.small) }
            if let status { Text(status).foregroundStyle(.secondary).lineLimit(2) }
        }
        .onAppear { hasStoredKey = Keychain.apiKey(for: profile.id) != nil }
    }

    private func saveKey() {
        do {
            try Keychain.setAPIKey(apiKey, for: profile.id)
            apiKey = ""
            hasStoredKey = true
            status = "Chiave salvata."
        } catch {
            status = error.localizedDescription
        }
    }

    private func test() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let reply = try await ChatClient(profile: profile).complete([
                ChatMessage(role: .user, content: "Rispondi solo con la parola OK."),
            ])
            status = "Funziona. Risposta: \(reply.prefix(40))"
        } catch {
            status = error.localizedDescription
        }
    }
}
