import AppKit
import TakkuCore
import SwiftUI

/// The Vault's Templates: created here and written in Obsidian, like the other notes.
struct TemplatesSection: View {
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
                        // Notes cannot go: Takku would create it again as the fallback Template.
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
