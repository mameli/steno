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
            SettingsView(models: controller.models)
        }
    }
}

private struct MenuBarLabel: View {
    let controller: MeetingController

    // While recording only the red dot: narrow, so it does not end up behind the notch.
    // The duration is in the menu.
    var body: some View {
        if controller.isShowingMark {
            Image(nsImage: .markIndicator)
        } else if controller.isInProgress {
            Image(nsImage: .recordingIndicator)
        } else if controller.processor.pendingCount > 0 {
            Image(systemName: "hourglass")
        } else {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel(Text(verbatim: "Steno"))
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
            ForEach(controller.silenceWarnings, id: \.self) { Text(verbatim: $0) }
            // The shortcut is global (GlobalHotKey): shown here as a reminder only, not as a menu key.
            Button("Stop meeting    ⌃⌥⌘R") { controller.stop() }
            Button("Mark this moment    ⌃⌥⌘M") { controller.mark() }
            if !controller.marks.isEmpty {
                Text("Marked moments: \(controller.marks.count)")
            }
            if !controller.isMarkHotKeyAvailable {
                Text("⌃⌥⌘M is already used by another app")
            }
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

        if let modelMenuTitle = controller.modelMenuTitle {
            Divider()
            Text(verbatim: modelMenuTitle)
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
            RecentMeetingsMenu(controller: controller)
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

        if let release = controller.updates.available {
            Divider()
            Button("Steno \(release.version) is available…") { controller.updates.openReleasePage() }
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

/// The last five Meetings: open the note, Retry.
private struct RecentMeetingsMenu: View {
    let controller: MeetingController

    var body: some View {
        Menu("Recent meetings") {
            ForEach(controller.processor.recent) { meeting in
                Menu(label(meeting)) {
                    Button("Open note") { controller.processor.openNote(meeting.id) }
                    // Only for a concluded Meeting: one being recorded or queued is left alone.
                    // It uses the Template and Summary Profile chosen in this menu.
                    if meeting.status.canRetry {
                        Button("Retry") {
                            controller.processor.retry(
                                meeting.id, templateName: controller.templateName,
                                profile: AppSettings.activeProviderProfile
                            )
                        }
                    }
                }
            }
            if let vault = Vault.configured {
                Divider()
                Button("Show all in Obsidian…") { vault.showMeetingsInObsidian() }
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

private extension NSImage {
    /// Red dot: menu bar images are monochrome unless `isTemplate` is turned off.
    static let recordingIndicator: NSImage = {
        let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: String(localized: "Meeting in progress"))!
            .withSymbolConfiguration(.init(paletteColors: [.white, .systemRed]))!
        image.isTemplate = false
        return image
    }()

    /// Shown for a second after a Mark, in the same red as the recording dot.
    static let markIndicator: NSImage = {
        let image = NSImage(systemSymbolName: "star.circle.fill", accessibilityDescription: String(localized: "Moment marked"))!
            .withSymbolConfiguration(.init(paletteColors: [.white, .systemRed]))!
        image.isTemplate = false
        return image
    }()
}

/// Quick switch of the Summary Profile (e.g. from a test one to an EU one).
private struct ProviderProfileMenu: View {
    @AppStorage(AppSettings.activeProviderProfileKey) private var activeID = ""
    /// Observed, not read once: Profiles added, renamed or deleted in Settings show up at once.
    @AppStorage(AppSettings.summaryProfilesKey) private var profilesData: Data?

    var body: some View {
        Picker("Summary Profile", selection: $activeID) {
            Text("Transcript").tag("")
            ForEach(AppSettings.decodeProfiles(profilesData)) { Text($0.displayName).tag($0.id.uuidString) }
        }
    }
}
