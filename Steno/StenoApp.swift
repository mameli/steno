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

    var body: some View {
        if controller.isInProgress {
            Button("Ferma riunione") { controller.stop() }
        } else {
            Button("Avvia riunione") { Task { await controller.start() } }
        }

        if controller.microphoneDenied {
            Divider()
            Button("Microfono non autorizzato: apri Impostazioni…") {
                controller.openMicrophoneSettings()
            }
        }

        if !controller.isInProgress {
            Divider()
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
