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

    // While recording only the red dot: narrow, so it does not end up behind the notch.
    // The duration is in the menu.
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
    @AppStorage(AppSettings.activeProviderProfileKey) private var activeProfileID = ""

    var body: some View {
        if controller.isInProgress {
            Text(verbatim: controller.recordingMenuTitle ?? "")
            // The shortcut is global (GlobalHotKey): shown here as a reminder only, not as a menu key.
            Button("Stop meeting    ⌃⌥⌘R") { controller.stop() }
        } else {
            Button("Start meeting    ⌃⌥⌘R") { Task { await controller.start() } }
        }
        if !controller.isHotKeyAvailable {
            Text("⌃⌥⌘R is already used by another app")
        }

        // With the "Transcript" Profile there is no Summary, so no Template to choose.
        if !activeProfileID.isEmpty {
            Picker("Template", selection: Bindable(controller).templateName) {
                ForEach(Vault.templateChoices(including: controller.templateName), id: \.self) { Text($0).tag($0) }
            }
        }
        // A Meeting's Profile is fixed at the start: changing it while recording would have no effect.
        if !controller.isInProgress {
            ProviderProfileMenu()
        }

        if controller.processor.pendingCount > 0 {
            Divider()
            if controller.processor.pendingCount == 1 {
                Text("Processing…")
            } else {
                Text("Processing… (\(controller.processor.pendingCount - 1) more queued)")
            }
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
            Button("Show last Recording in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([directory])
            }
        }
        if controller.processor.lastTranscriptURL != nil {
            Button("Open last Transcript") { controller.processor.openLastTranscript() }
        }
        #endif

        if controller.microphoneDenied {
            Divider()
            Button("Microphone not authorized: open System Settings…") {
                controller.openMicrophoneSettings()
            }
        }

        Divider()
        Button("Settings…") {
            // Steno has no Dock icon: without activating it the window would stay behind the others.
            NSApplication.shared.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        if !controller.isInProgress {
            Button("Quit Steno") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

/// The last five Meetings: open the note, Retry, Regenerate with another Template or Profile.
private struct RecentMeetingsMenu: View {
    let processor: MeetingProcessor

    var body: some View {
        Menu("Recent meetings") {
            ForEach(processor.recent) { meeting in
                Menu(label(meeting)) {
                    Button("Open note") { processor.openNote(meeting.id) }
                    // Retry and Regenerate only for a concluded Meeting: one being recorded or queued is left alone.
                    if meeting.status.canRetry {
                        if meeting.hasAudio {
                            Button("Retry") { processor.retry(meeting.id) }
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
        if meeting.hasSummaryProfile {
            Menu("Regenerate with Template") {
                ForEach(Vault.templateChoices(including: AppSettings.defaultTemplate), id: \.self) { name in
                    Button(name) { processor.regenerate(meeting.id, templateName: name) }
                }
            }
        }
        Menu("Regenerate with Profile") {
            ForEach(AppSettings.summaryProfiles) { profile in
                Button(profile.displayName) { processor.regenerate(meeting.id, profile: profile) }
            }
        }
    }
}

private extension NSImage {
    /// Red dot: menu bar images are monochrome unless `isTemplate` is turned off.
    static let recordingIndicator: NSImage = {
        let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: String(localized: "Meeting in progress"))!
            .withSymbolConfiguration(.init(paletteColors: [.white, .systemRed]))!
        image.isTemplate = false
        return image
    }()
}

/// Quick switch of the Summary Profile (e.g. from a test one to an EU one).
private struct ProviderProfileMenu: View {
    @AppStorage(AppSettings.activeProviderProfileKey) private var activeID = ""

    var body: some View {
        Picker("Summary Profile", selection: $activeID) {
            Text("Transcript").tag("")
            ForEach(AppSettings.summaryProfiles) { Text($0.displayName).tag($0.id.uuidString) }
        }
    }
}
