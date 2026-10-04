import AppKit
@preconcurrency import UserNotifications

/// Notifiche di fine Elaborazione. Un clic su "Riepilogo pronto" apre la nota in Obsidian.
@MainActor
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifications()
    private nonisolated static let noteKey = "notePath"

    private var isAuthorized = false

    /// Chiede il permesso una volta, all'avvio dell'app.
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Task {
            isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    func notify(title: String, body: String, note: URL?) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let note { content.userInfo = [Self.noteKey: note.path(percentEncoded: false)] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let path = response.notification.request.content.userInfo[Self.noteKey] as? String else { return }
        await MainActor.run { Vault.openInObsidian(URL(filePath: path)) }
    }

    /// Steno non ha finestre in primo piano: senza questo le notifiche non comparirebbero mai.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
