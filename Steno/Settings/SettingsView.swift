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
            LabeledContent("Nome") {
                PasteableTextField(placeholder: "es. Mistral UE", text: $profile.name)
            }
            LabeledContent("URL base") {
                PasteableTextField(placeholder: "es. https://api.mistral.ai/v1", text: $profile.baseURL)
            }
            LabeledContent("Modello") {
                PasteableTextField(placeholder: "es. mistral-medium-latest", text: $profile.model)
            }
            TextField("Contesto massimo (token)", value: $profile.maxContextTokens, format: .number)

            // L'unico punto in cui si inserisce la chiave: si salva nel Portachiavi appena incollata.
            LabeledContent("Chiave API") {
                HStack {
                    PasteableTextField(
                        placeholder: hasStoredKey ? "Salvata nel Portachiavi · incolla qui per sostituirla" : "Incolla qui la chiave",
                        text: $apiKey,
                        isSecure: true
                    )
                    if hasStoredKey && apiKey.isEmpty {
                        Button("Rimuovi", role: .destructive) {
                            Keychain.deleteAPIKey(for: profile.id)
                            hasStoredKey = false
                            status = "Chiave rimossa."
                        }
                    }
                }
            }
            .onChange(of: apiKey) { saveKey() }

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

    private func saveKey() {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try Keychain.setAPIKey(apiKey, for: profile.id)
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
