import AppKit
import StenoCore
import SwiftUI

/// The Vault's Vocabulary: one file, written in Obsidian like the Templates.
struct VocabularySection: View {
    /// Changes when another Vault is chosen: the count must be read again.
    let vaultPath: String
    @State private var entryCount = 0
    @State private var status: String?

    var body: some View {
        Section {
            if Vault.configured == nil {
                Text("Choose the Vault first.").foregroundStyle(.secondary)
            } else {
                LabeledContent("Entries") {
                    HStack {
                        Text(entryCount, format: .number)
                        Button("Open Vocabulary", action: open)
                    }
                }
                if let status {
                    Text(status).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Vocabulary")
        } footer: {
            Text("Names and technical words that recognition gets wrong, in Meetings/_Vocabulary.md in the Vault. The Summary uses them; the variants you list are fixed in the Transcript.")
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: reload)
        .onChange(of: vaultPath) { reload() }
        // Back from Obsidian after editing the file.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
    }

    private func reload() {
        entryCount = Vault.configured?.vocabulary().entries.count ?? 0
    }

    private func open() {
        guard let vault = Vault.configured else { return }
        do {
            if try vault.ensureVocabularyFile() {
                Vault.openNewFileInObsidian(vault.vocabularyURL)
            } else {
                Vault.openInObsidian(vault.vocabularyURL)
            }
            status = nil
        } catch {
            status = error.localizedDescription
        }
        reload()
    }
}
