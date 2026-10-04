import Foundation

/// Scrive il Riepilogo con un Provider: in una richiesta se la Trascrizione entra nel contesto
/// del modello, altrimenti riassumendo a blocchi e unendo i riassunti parziali.
public struct Summarizer: Sendable {
    private let client: ChatClient
    private let maxContextTokens: Int

    /// Sotto questo contesto non resta spazio utile per la Trascrizione dopo regole e risposta.
    public static let minimumContextTokens = 8_192

    public init(client: ChatClient, maxContextTokens: Int) {
        self.client = client
        self.maxContextTokens = max(maxContextTokens, Self.minimumContextTokens)
    }

    public func summarize(_ prompt: SummaryPrompt) async throws -> String {
        if prompt.fits(maxContextTokens: maxContextTokens) {
            return try await client.complete(prompt.singleRequest())
        }
        var partials = try await complete(prompt.partialRequests(maxContextTokens: maxContextTokens))
        // Riunioni molto lunghe: si uniscono i riassunti a gruppi finché l'unione finale entra nel contesto.
        while !prompt.mergeFits(partials: partials, maxContextTokens: maxContextTokens) {
            let groups = prompt.groupRequests(partials: partials, maxContextTokens: maxContextTokens)
            guard groups.count < partials.count else { break }
            partials = try await complete(groups)
        }
        return try await client.complete(prompt.mergeRequest(partials: partials))
    }

    private func complete(_ requests: [[ChatMessage]]) async throws -> [String] {
        var replies: [String] = []
        for request in requests {
            replies.append(try await client.complete(request))
        }
        return replies
    }
}
