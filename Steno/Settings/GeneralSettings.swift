import AppKit
import ServiceManagement
import SwiftUI

/// Icon, name and version at the top of Settings.
struct AppIdentity: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 4) {
            // From the asset catalog: the icon macOS caches for the app can be an old one.
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text(verbatim: "Steno").font(.title2.bold()).foregroundStyle(.primary)
            Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

/// Starts Steno when the user logs in, as a login item registered with macOS: it also appears,
/// and can be turned off, in System Settings → General → Login Items.
struct LaunchAtLoginToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var error: String?

    var body: some View {
        Toggle("Open at login", isOn: Binding(
            get: { status == .enabled || status == .requiresApproval },
            set: setEnabled
        ))
        // The status can change in System Settings while this window is closed.
        .onAppear { status = SMAppService.mainApp.status }
        if status == .requiresApproval {
            HStack {
                Text("Allow Steno in System Settings → Login Items.").foregroundStyle(.secondary)
                Spacer()
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        if let error {
            Text(error).foregroundStyle(.secondary)
        }
    }

    private func setEnabled(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}

/// The daily question to GitHub about a newer release.
struct UpdatesToggle: View {
    @AppStorage(AppSettings.checkForUpdatesKey) private var checkForUpdates = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Check for updates", isOn: $checkForUpdates)
            Text("Once a day Steno asks GitHub for the latest version; nothing about you or your Meetings is sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Notifications that suggest starting and stopping a Meeting when a call app takes and releases the microphone.
struct SuggestCallsToggle: View {
    @AppStorage(AppSettings.suggestCallsKey) private var suggestCalls = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Suggest recording when a call starts", isOn: $suggestCalls)
            Text("A notification when an app uses the microphone for a while, and another when it stops. Steno never starts or stops by itself.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Names the Meeting note after the calendar event in progress and lists its participants.
/// Turning it on asks macOS for access to the calendars; without it the switch goes back off.
struct CalendarToggle: View {
    @AppStorage(AppSettings.useCalendarKey) private var useCalendar = false
    @State private var isDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Use the calendar", isOn: Binding(get: { useCalendar }, set: setEnabled))
            Text("The Meeting note takes the name and the participants of the event in progress.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // Access can be revoked in System Settings while Steno is running.
        .onAppear { if useCalendar && !MeetingCalendar.isAuthorized { useCalendar = false } }
        if isDenied {
            HStack {
                Text("Allow Steno in System Settings → Privacy & Security → Calendars.").foregroundStyle(.secondary)
                Spacer()
                Button("Open Calendars") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
            }
        }
    }

    private func setEnabled(_ isEnabled: Bool) {
        guard isEnabled else {
            useCalendar = false
            return
        }
        Task {
            let granted = await MeetingCalendar.requestAccess()
            useCalendar = granted
            isDenied = !granted
        }
    }
}
