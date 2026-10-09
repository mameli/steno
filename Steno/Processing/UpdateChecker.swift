import AppKit
import Observation
import StenoCore
import os

private let logger = Logger(subsystem: "dev.mameli.steno", category: "updates")

/// At launch and once a day, when the user leaves it on in Settings, asks GitHub for the latest
/// release. The request carries nothing about the user or the Meetings.
@MainActor
@Observable
final class UpdateChecker {
    struct Release: Equatable {
        let version: String
        let page: URL
    }

    private static let latestRelease = URL(string: "https://api.github.com/repos/mameli/steno/releases/latest")!

    /// A release newer than the running app, shown in the menu.
    private(set) var available: Release?

    func start() {
        Task { [weak self] in
            while true {
                guard let self else { return }
                if AppSettings.checkForUpdates { await self.check() }
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
    }

    func openReleasePage() {
        if let available { NSWorkspace.shared.open(available.page) }
    }

    private func check() async {
        struct Reply: Decodable {
            let tag: String
            let page: URL

            enum CodingKeys: String, CodingKey {
                case tag = "tag_name"
                case page = "html_url"
            }
        }
        var request = URLRequest(url: Self.latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            guard let version = AppVersion.fromTag(reply.tag), AppVersion.isNewer(version, than: current) else {
                available = nil
                return
            }
            available = Release(version: version, page: reply.page)
        } catch {
            // Offline or rate-limited: nothing to show, tried again tomorrow.
            logger.notice("Update check failed: \(error, privacy: .public)")
        }
    }
}
