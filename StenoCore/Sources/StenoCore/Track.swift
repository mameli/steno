/// Una delle due sorgenti audio di una Registrazione.
public enum Track: String, Codable, Sendable, CaseIterable {
    /// Il microfono.
    case me = "io"
    /// L'audio di sistema.
    case others = "altri"

    /// Come la Traccia compare nella Trascrizione.
    public var label: String {
        switch self {
        case .me: "Io"
        case .others: "Altri"
        }
    }
}
