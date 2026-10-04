import Foundation

public struct ChatMessage: Codable, Equatable, Sendable {
    public enum Sender: String, Codable, Sendable {
        case system, user, assistant
    }

    public let role: Sender
    public let content: String

    public init(role: Sender, content: String) {
        self.role = role
        self.content = content
    }
}

/// Client per qualsiasi server con API compatibile OpenAI (`POST {baseURL}/chat/completions`):
/// provider remoti e server locali come llama.cpp o Ollama (ADR 0004).
public struct ChatClient: Sendable {
    public enum Failure: LocalizedError, Equatable {
        /// Il provider ha risposto con un errore: stato HTTP e messaggio così come li manda.
        case http(status: Int, message: String)
        /// Nessun testo utilizzabile nella risposta.
        case emptyReply
        /// Il modello si è fermato per il limite di lunghezza: la risposta è a metà.
        case truncated

        public var errorDescription: String? {
            switch self {
            case .http(let status, let message): "Il provider ha risposto con l'errore \(status): \(message)"
            case .emptyReply: "Il provider non ha restituito testo."
            case .truncated: "La risposta del modello è stata troncata per il limite di lunghezza."
            }
        }
    }

    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let baseURL: URL
    private let apiKey: String?
    private let model: String
    private let transport: Transport

    public init(baseURL: URL, apiKey: String?, model: String, transport: @escaping Transport) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.transport = transport
    }

    public func complete(_ messages: [ChatMessage]) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(RequestBody(model: model, messages: messages))

        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Failure.http(status: response.statusCode, message: Self.errorMessage(in: data))
        }
        let choice = (try? JSONDecoder().decode(ResponseBody.self, from: data))?.choices.first
        guard choice?.finishReason != "length" else { throw Failure.truncated }
        guard let reply = choice?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty else {
            throw Failure.emptyReply
        }
        return reply
    }

    /// Il messaggio d'errore nel formato OpenAI (`{"error":{"message":…}}`), altrimenti il testo grezzo.
    private static func errorMessage(in data: Data) -> String {
        struct ErrorBody: Decodable {
            struct Detail: Decodable { let message: String }
            let error: Detail
        }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            return body.error.message
        }
        return String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [ChatMessage]
    }

    private struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }
        let choices: [Choice]
    }
}
