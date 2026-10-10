import Foundation

/// A named configuration of a Provider for the Summary. The API key is not stored here:
/// it lives in the Keychain, under the Profile's identifier.
public struct ProviderProfile: Codable, Identifiable, Equatable, Hashable, Sendable {
    public static let defaultMaxContextTokens = 32_000

    public var id: UUID
    public var name: String
    public var baseURL: String
    public var model: String
    /// Tokens the model accepts in one request: beyond that the Transcript is split into blocks.
    public var maxContextTokens: Int

    public init(id: UUID = UUID(), name: String, baseURL: String, model: String, maxContextTokens: Int) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.maxContextTokens = maxContextTokens
    }

    public enum URLError: LocalizedError, Equatable {
        case invalid(String)
        case insecure(String)

        public var errorDescription: String? {
            switch self {
            case .invalid(let url):
                String(localized: "Invalid Profile URL: \"\(url)\" (http:// or https:// and an address are needed).")
            case .insecure(let url):
                String(localized: "Plain-text Profile URL: \"\(url)\". Use https://; http:// is allowed only for servers on this Mac.")
            }
        }
    }

    /// Plain HTTP only towards this Mac: to any other machine, even on the local network,
    /// the key and the Transcript would travel readable.
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// The base URL to call, if it is usable.
    public func validatedBaseURL() throws -> URL {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host(), !host.isEmpty
        else { throw URLError.invalid(baseURL) }
        guard scheme == "https" || Self.loopbackHosts.contains(host.lowercased()) else {
            throw URLError.insecure(baseURL)
        }
        return url
    }

    /// Whether the provider is a server on this Mac (llama.cpp, Ollama, LM Studio).
    public var runsOnThisMac: Bool {
        guard let host = URL(string: baseURL.trimmingCharacters(in: .whitespaces))?.host() else { return false }
        return Self.loopbackHosts.contains(host.lowercased())
    }

    /// The name shown in menus, even when the user did not type one. "Untitled" is looked up
    /// in the app's string catalog (Bundle.main), so the app can translate it.
    public var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Untitled") : name
    }
}
