import AppKit
import SwiftUI

@main
struct StenoApp: App {
    @State private var controller = MeetingController()

    var body: some Scene {
        MenuBarExtra {
            MeetingMenu(controller: controller)
        } label: {
            MenuBarLabel(controller: controller)
                #if DEBUG
                .task { await controller.runSmokeTestIfRequested() }
                #endif
        }

        Settings {
            SettingsView()
        }
    }
}

private struct MenuBarLabel: View {
    let controller: MeetingController

    var body: some View {
        if let elapsedText = controller.elapsedText {
            Image(nsImage: .recordingIndicator)
            Text(elapsedText)
        } else {
            Image(systemName: "waveform")
        }
    }
}

private struct MeetingMenu: View {
    let controller: MeetingController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if controller.isInProgress {
            Button("Ferma riunione") { controller.stop() }
        } else {
            Button("Avvia riunione") { Task { await controller.start() } }
        }

        Picker("Template", selection: Bindable(controller).templateName) {
            ForEach(Vault.templateChoices(including: controller.templateName), id: \.self) { Text($0).tag($0) }
        }
        // Il Profilo di una Riunione si fissa all'avvio: cambiarlo durante la registrazione non avrebbe effetto.
        if !controller.isInProgress {
            ProviderProfileMenu()
        }

        if controller.processingCount > 0 {
            Divider()
            Text("Elaborazione in corso…")
        }

        if let lastError = controller.lastError {
            Divider()
            Text("⚠️ \(lastError)")
        }

        #if DEBUG
        if let directory = controller.lastRecordingDirectory, !controller.isInProgress {
            Button("Mostra ultima Registrazione nel Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([directory])
            }
        }
        if let transcript = controller.lastTranscriptURL {
            Button("Apri ultima Trascrizione") { NSWorkspace.shared.open(transcript) }
        }
        if let note = controller.lastNoteURL {
            Button("Apri ultima Nota della Riunione") { Vault.openInObsidian(note) }
        }
        #endif

        if controller.microphoneDenied {
            Divider()
            Button("Microfono non autorizzato: apri Impostazioni…") {
                controller.openMicrophoneSettings()
            }
        }

        Divider()
        Button("Impostazioni…") {
            // Steno non ha icona nel Dock: senza attivarla la finestra resterebbe dietro le altre.
            NSApplication.shared.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        if !controller.isInProgress {
            Button("Esci da Steno") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

private extension NSImage {
    /// Pallino rosso: le immagini della barra dei menu sono monocromatiche
    /// a meno di disattivare `isTemplate`.
    static let recordingIndicator: NSImage = {
        let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Riunione in corso")!
            .withSymbolConfiguration(.init(paletteColors: [.white, .systemRed]))!
        image.isTemplate = false
        return image
    }()
}

/// Cambio rapido del Profilo per il Riepilogo (es. da uno di prova a uno UE).
private struct ProviderProfileMenu: View {
    @AppStorage(AppSettings.activeProviderProfileKey) private var activeID = ""

    var body: some View {
        Picker("Profilo Riepilogo", selection: $activeID) {
            Text("Nessuno").tag("")
            ForEach(AppSettings.summaryProfiles) { Text($0.displayName).tag($0.id.uuidString) }
        }
    }
}
