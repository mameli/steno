import Foundation
import Testing
import StenoCore

/// Registra le richieste e restituisce risposte preparate: nessuna chiamata di rete.
final class StubTransport: @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private let respond: (Int) -> (status: Int, body: String)

    init(status: Int = 200, body: String) {
        respond = { _ in (status, body) }
    }

    /// `reply(n)` è il testo della risposta alla richiesta numero `n` (da 0).
    init(reply: @escaping (Int) -> String) {
        respond = { index in
            let content = String(data: try! JSONEncoder().encode(reply(index)), encoding: .utf8)!
            return (200, #"{"choices":[{"message":{"role":"assistant","content":"# + content + "}}]}")
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = respond(requests.count)
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }

    /// Il testo del messaggio `role` della richiesta numero `index`.
    func message(_ index: Int, _ role: String) -> String? {
        guard let body = requests[index].httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let messages = json["messages"] as? [[String: String]]
        else { return nil }
        return messages.first { $0["role"] == role }?["content"]
    }
}

@Suite("Client compatibile OpenAI")
struct ChatClientTests {
    let messages = [ChatMessage(role: .system, content: "Sei Steno."), ChatMessage(role: .user, content: "Riassumi.")]

    @Test("la richiesta va a chat/completions con modello, messaggi e chiave")
    func request() async throws {
        let stub = StubTransport(body: #"{"choices":[{"message":{"role":"assistant","content":"Ok."}}]}"#)
        let client = ChatClient(
            baseURL: URL(string: "https://openrouter.ai/api/v1")!, apiKey: "sk-test", model: "openai/gpt-6-luna",
            transport: stub.send
        )

        _ = try await client.complete(messages)

        let request = try #require(stub.requests.first)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "openai/gpt-6-luna")
        let sent = try #require(body["messages"] as? [[String: String]])
        #expect(sent == [["role": "system", "content": "Sei Steno."], ["role": "user", "content": "Riassumi."]])
    }

    @Test("senza chiave (server locale) non c'è l'intestazione Authorization; la risposta è ripulita dagli spazi")
    func localServer() async throws {
        let stub = StubTransport(body: #"{"choices":[{"message":{"role":"assistant","content":"\n  ## Sintesi\nTutto ok.\n\n"}}]}"#)
        let client = ChatClient(
            baseURL: URL(string: "http://localhost:8080/v1/")!, apiKey: nil, model: "locale", transport: stub.send
        )

        let reply = try await client.complete(messages)

        #expect(reply == "## Sintesi\nTutto ok.")
        #expect(stub.requests.first?.url?.absoluteString == "http://localhost:8080/v1/chat/completions")
        #expect(stub.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("un errore HTTP riporta lo stato e il messaggio del provider")
    func httpError() async {
        let stub = StubTransport(status: 401, body: #"{"error":{"message":"No auth credentials found","code":401}}"#)
        let client = ChatClient(baseURL: URL(string: "https://x.example/v1")!, apiKey: "sbagliata", model: "m", transport: stub.send)

        await #expect(throws: ChatClient.Failure.http(status: 401, message: "No auth credentials found")) {
            try await client.complete(messages)
        }
    }

    @Test("un errore HTTP senza corpo JSON riporta il testo grezzo")
    func httpErrorWithoutJSON() async {
        let stub = StubTransport(status: 502, body: "Bad Gateway")
        let client = ChatClient(baseURL: URL(string: "https://x.example/v1")!, apiKey: nil, model: "m", transport: stub.send)

        await #expect(throws: ChatClient.Failure.http(status: 502, message: "Bad Gateway")) {
            try await client.complete(messages)
        }
    }

    @Test("una risposta senza testo è un errore, non un Riepilogo vuoto", arguments: [
        #"{"choices":[{"message":{"role":"assistant","content":"   "}}]}"#,
        #"{"choices":[{"message":{"role":"assistant","content":null}}]}"#,
        #"{"choices":[]}"#,
        "non è JSON",
    ])
    func emptyReply(body: String) async {
        let stub = StubTransport(body: body)
        let client = ChatClient(baseURL: URL(string: "https://x.example/v1")!, apiKey: nil, model: "m", transport: stub.send)

        await #expect(throws: ChatClient.Failure.emptyReply) {
            try await client.complete(messages)
        }
    }

    @Test("una risposta troncata per limite di lunghezza è un errore, non un Riepilogo a metà")
    func truncated() async {
        let stub = StubTransport(body: ###"{"choices":[{"message":{"role":"assistant","content":"## Sintesi\nIl budget"},"finish_reason":"length"}]}"###)
        let client = ChatClient(baseURL: URL(string: "https://x.example/v1")!, apiKey: nil, model: "m", transport: stub.send)

        await #expect(throws: ChatClient.Failure.truncated) {
            try await client.complete(messages)
        }
    }
}
