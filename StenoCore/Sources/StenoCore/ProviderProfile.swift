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

    /// The name shown in menus, even when the user did not type one. "Untitled" is looked up
    /// in the app's string catalog (Bundle.main), so the app can translate it.
    public var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Untitled") : name
    }
}
