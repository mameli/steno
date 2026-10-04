import Foundation

/// Una configurazione con nome di un Provider per il Riepilogo. La chiave API non sta qui:
/// è nel Portachiavi, sotto l'identificativo del Profilo.
public struct ProviderProfile: Codable, Identifiable, Equatable, Hashable, Sendable {
    public static let defaultMaxContextTokens = 32_000

    public var id: UUID
    public var name: String
    public var baseURL: String
    public var model: String
    /// Token che il modello accetta in una richiesta: oltre, la Trascrizione si divide in blocchi.
    public var maxContextTokens: Int

    public init(id: UUID = UUID(), name: String, baseURL: String, model: String, maxContextTokens: Int) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.maxContextTokens = maxContextTokens
    }

    /// Il nome da mostrare nei menu, anche se l'utente non ne ha scritto uno.
    public var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Senza nome" : name
    }
}
