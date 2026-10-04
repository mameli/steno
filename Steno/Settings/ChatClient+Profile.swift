import Foundation
import StenoCore

extension ChatClient {
    /// A slow local model can go minutes without sending a byte before answering:
    /// the default timeout (60 s of silence) is not enough.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 900
        configuration.timeoutIntervalForResource = 1_800
        return URLSession(configuration: configuration)
    }()

    init(profile: ProviderProfile) throws {
        guard let url = URL(string: profile.baseURL.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host()
        else {
            throw ProfileError.invalidURL(profile.baseURL)
        }
        // Plain HTTP only towards this Mac or the local network: otherwise key and Transcript would travel readable.
        guard scheme == "https" || ["localhost", "127.0.0.1", "::1"].contains(host) || host.hasSuffix(".local") else {
            throw ProfileError.insecureURL(profile.baseURL)
        }
        self.init(baseURL: url, apiKey: Keychain.apiKey(for: profile.id), model: profile.model) { request in
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, http)
        }
    }
}

enum ProfileError: LocalizedError {
    case invalidURL(String)
    case insecureURL(String)
    case noActiveProfile

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            String(localized: "Invalid Profile URL: \"\(url)\" (http:// or https:// and an address are needed).")
        case .insecureURL(let url):
            String(localized: "Plain-text Profile URL: \"\(url)\". Use https://; http:// is allowed only for servers on this Mac.")
        case .noActiveProfile:
            String(localized: "No Profile for the Summary: choose one in Settings.")
        }
    }
}
