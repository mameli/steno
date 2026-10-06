import AppKit
import os
@preconcurrency import UserNotifications

private let logger = Logger(subsystem: "dev.mameli.steno", category: "notifications")

/// End-of-Processing notifications. Clicking "Summary ready" opens the note in Obsidian.
@MainActor
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifications()
    private nonisolated static let noteKey = "notePath"

    /// Asks for permission once, at app launch.
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Task {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                logger.info("Notification permission requested: granted \(granted, privacy: .public)")
            } catch {
                logger.error("Notification permission request failed: \(error, privacy: .public)")
            }
        }
    }

    /// The permission is read at every notification, not once at launch: it can be turned on in
    /// System Settings while Steno is running.
    func notify(title: String, body: String, note: URL?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let note { content.userInfo = [Self.noteKey: note.path(percentEncoded: false)] }
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else {
                logger.notice("Notification \"\(title, privacy: .public)\" not shown: permission status \(status.rawValue, privacy: .public)")
                return
            }
            do {
                try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            } catch {
                logger.error("Notification \"\(title, privacy: .public)\" not delivered: \(error, privacy: .public)")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let path = response.notification.request.content.userInfo[Self.noteKey] as? String else { return }
        await MainActor.run { Vault.openInObsidian(URL(filePath: path)) }
    }

    /// Steno has no window in the foreground: without this, notifications would never show.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
