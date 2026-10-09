import Foundation
import TakkuCore

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
        let url = try profile.validatedBaseURL()
        self.init(baseURL: url, apiKey: Keychain.apiKey(for: profile.id), model: profile.model) { request in
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, http)
        }
    }
}
