import AppKit
import StenoCore
import SwiftUI

/// Finestra Impostazioni essenziale: Vault, Template di default, Profili per il Riepilogo.
struct SettingsView: View {
    @State private var vaultPath = AppSettings.vaultPath ?? ""
    @State private var profiles = AppSettings.summaryProfiles
    @AppStorage(AppSettings.activeProviderProfileKey) private var activeProfileID = ""
    @State private var selectedProfileID = AppSettings.activeProviderProfile?.id ?? AppSettings.summaryProfiles.first?.id
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
                if profiles.isEmpty {
                    Text("Nessun Profilo. Aggiungine uno per generare i Riepiloghi.")
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
                    Button("Aggiungi Profilo", action: addProfile)
                    Spacer()
                    Button("Elimina", role: .destructive, action: deleteSelectedProfile)
                        .disabled(selectedProfileID == nil)
                }
            } header: {
                Text("Profili per il Riepilogo")
            } footer: {
                Text("Qualsiasi server con API compatibile OpenAI. Per le riunioni di lavoro usa solo Provider locali o con sede e dati in UE.")
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
        panel.prompt = "Usa questo Vault"
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
                Text(profile.model.isEmpty ? "Da configurare" : profile.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Text("In uso").font(.caption).foregroundStyle(.green)
            }
        }
    }
}

private struct ProfileEditor: View {
    @Binding var profile: ProviderProfile
    let isActive: Bool
    let activate: () -> Void
    @State private var apiKey = ""
    @State private var hasStoredKey = false
    @State private var status: String?
    @State private var isTesting = false

    var body: some View {
        Section("Profilo: \(profile.displayName)") {
            TextField("Nome", text: $profile.name, prompt: Text("es. Mistral UE"))
            TextField("URL base", text: $profile.baseURL, prompt: Text("es. https://api.mistral.ai/v1"))
            TextField("Modello", text: $profile.model, prompt: Text("es. mistral-medium-latest"))
            TextField("Contesto massimo (token)", value: $profile.maxContextTokens, format: .number)

            LabeledContent("Chiave API") {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(hasStoredKey ? "Salvata nel Portachiavi" : "Nessuna (va bene per i server locali)")
                        .foregroundStyle(hasStoredKey ? .green : .secondary)
                    HStack {
                        // Le app nella barra dei menu non hanno il menu Composizione: ⌘V nei campi
                        // non sempre funziona, questo pulsante legge direttamente dagli appunti.
                        Button("Incolla e salva") { pasteKey() }
                        if hasStoredKey {
                            Button("Rimuovi", role: .destructive) {
                                Keychain.deleteAPIKey(for: profile.id)
                                hasStoredKey = false
                                status = "Chiave rimossa."
                            }
                        }
                    }
                }
            }
            LabeledContent("Oppure scrivila") {
                HStack {
                    SecureField("", text: $apiKey, prompt: Text("chiave API"))
                    Button("Salva") { save(apiKey) }
                        .disabled(apiKey.isEmpty)
                }
            }

            HStack {
                Button("Prova connessione") { Task { await test() } }
                    .disabled(isTesting || profile.baseURL.isEmpty || profile.model.isEmpty)
                if isTesting { ProgressView().controlSize(.small) }
                Spacer()
                if isActive {
                    Text("In uso per i Riepiloghi").foregroundStyle(.green)
                } else {
                    Button("Usa per i Riepiloghi", action: activate)
                }
            }
            if let status {
                Text(status).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .onAppear { hasStoredKey = Keychain.apiKey(for: profile.id) != nil }
    }

    private func pasteKey() {
        guard let key = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else {
            status = "Negli appunti non c'è testo: copia prima la chiave."
            return
        }
        save(key)
    }

    private func save(_ key: String) {
        do {
            try Keychain.setAPIKey(key, for: profile.id)
            apiKey = ""
            hasStoredKey = true
            status = "Chiave salvata nel Portachiavi."
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
