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

    // Durante la registrazione solo il pallino rosso: stretto, non finisce dietro la tacca.
    // La durata si legge aprendo il menu.
    var body: some View {
        if controller.isInProgress {
            Image(nsImage: .recordingIndicator)
        } else if controller.processor.pendingCount > 0 {
            Image(systemName: "hourglass")
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
            Text("In registrazione · \(controller.elapsedText ?? "")")
            // La scorciatoia è globale (GlobalHotKey): qui solo come promemoria, non come tasto del menu.
            Button("Ferma riunione    ⌃⌥⌘R") { controller.stop() }
        } else {
            Button("Avvia riunione    ⌃⌥⌘R") { Task { await controller.start() } }
        }
        if !controller.isHotKeyAvailable {
            Text("⌃⌥⌘R è già usata da un'altra app")
        }

        Picker("Template", selection: Bindable(controller).templateName) {
            ForEach(Vault.templateChoices(including: controller.templateName), id: \.self) { Text($0).tag($0) }
        }
        // Il Profilo di una Riunione si fissa all'avvio: cambiarlo durante la registrazione non avrebbe effetto.
        if !controller.isInProgress {
            ProviderProfileMenu()
        }

        if controller.processor.pendingCount > 0 {
            Divider()
            Text(controller.processor.pendingCount == 1
                ? "Elaborazione in corso…"
                : "Elaborazione in corso… (altre \(controller.processor.pendingCount - 1) in coda)")
        }

        if let lastError = controller.lastError {
            Divider()
            Text("⚠️ \(lastError)")
        }

        if !controller.processor.recent.isEmpty {
            Divider()
            RecentMeetingsMenu(processor: controller.processor)
        }

        #if DEBUG
        if let directory = controller.lastRecordingDirectory, !controller.isInProgress {
            Button("Mostra ultima Registrazione nel Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([directory])
            }
        }
        if let transcript = controller.processor.lastTranscriptURL {
            Button("Apri ultima Trascrizione") { NSWorkspace.shared.open(transcript) }
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

/// Le ultime cinque Riunioni: apri la nota, Riprova, Rigenera con un altro Template o Profilo.
private struct RecentMeetingsMenu: View {
    let processor: MeetingProcessor

    var body: some View {
        Menu("Riunioni recenti") {
            ForEach(processor.recent) { meeting in
                Menu(label(meeting)) {
                    Button("Apri nota") { processor.openNote(meeting.id) }
                    // Riprova e Rigenera solo a Riunione conclusa: non si tocca una in registrazione o in coda.
                    if meeting.status.canRetry {
                        if meeting.hasAudio {
                            Button("Riprova") { processor.retry(meeting.id) }
                        }
                        RegenerateMenus(processor: processor, meeting: meeting)
                    }
                }
            }
        }
    }

    private func label(_ meeting: MeetingProcessor.RecentMeeting) -> String {
        switch meeting.status {
        case .recording: "⏺ \(meeting.title)"
        case .queued, .processing, .regenerating: "⏳ \(meeting.title)"
        case .completed: meeting.title
        case .failed: "⚠️ \(meeting.title)"
        }
    }
}

private struct RegenerateMenus: View {
    let processor: MeetingProcessor
    let meeting: MeetingProcessor.RecentMeeting

    var body: some View {
        Menu("Rigenera con Template") {
            ForEach(Vault.templateChoices(including: AppSettings.defaultTemplate), id: \.self) { name in
                Button(name) { processor.regenerate(meeting.id, templateName: name) }
            }
        }
        Menu("Rigenera con Profilo") {
            ForEach(AppSettings.summaryProfiles) { profile in
                Button(profile.displayName) { processor.regenerate(meeting.id, profile: profile) }
            }
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
