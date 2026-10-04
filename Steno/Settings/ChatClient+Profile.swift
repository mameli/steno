import Foundation
import StenoCore

extension ChatClient {
    /// Un modello locale lento può restare minuti senza mandare un byte prima di rispondere:
    /// il timeout di default (60 s di silenzio) non basta.
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
        // In chiaro solo verso questo Mac o la rete locale: altrimenti chiave e Trascrizione viaggerebbero leggibili.
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
        case .invalidURL(let url): "URL del Profilo non valido: \"\(url)\" (serve http:// o https:// e un indirizzo)."
        case .insecureURL(let url): "URL del Profilo in chiaro: \"\(url)\". Usa https://, http:// è ammesso solo per i server su questo Mac."
        case .noActiveProfile: "Nessun Profilo per il Riepilogo: scegline uno nelle Impostazioni."
        }
    }
}
