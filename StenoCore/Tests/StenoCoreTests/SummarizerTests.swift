import Foundation
import Testing
import StenoCore

@Suite("Riepilogo in una o più richieste")
struct SummarizerTests {
    let template = Template(fileName: "Generico", content: "## Sintesi\n## Azioni")

    /// `count` paragrafi alternati Altri/Io, ciascuno di circa 300 caratteri.
    func transcript(paragraphs count: Int) -> Transcript {
        Transcript(utterances: (0..<count).map { index in
            Utterance(
                track: index.isMultiple(of: 2) ? .others : .me,
                start: Double(index * 20), end: Double(index * 20 + 15),
                text: "Paragrafo \(index): " + String(repeating: "parole della riunione ", count: 14)
            )
        })
    }

    func client(_ stub: StubTransport) -> ChatClient {
        ChatClient(baseURL: URL(string: "https://x.example/v1")!, apiKey: nil, model: "m", transport: stub.send)
    }

    @Test("se la Trascrizione entra nel contesto basta una richiesta")
    func single() async throws {
        let stub = StubTransport { _ in "## Sintesi\nTutto." }
        let prompt = SummaryPrompt(template: template, personalNotes: "", transcript: transcript(paragraphs: 6), meetingLanguage: "it")

        let summary = try await Summarizer(client: client(stub), maxContextTokens: 32_000).summarize(prompt)

        #expect(summary == "## Sintesi\nTutto.")
        #expect(stub.requests.count == 1)
    }

    @Test("se non entra si riassume a blocchi in ordine e si uniscono i riassunti parziali con il Template")
    func chunked() async throws {
        let stub = StubTransport { index in "riassunto \(index + 1)" }
        let full = transcript(paragraphs: 40)
        let prompt = SummaryPrompt(template: template, personalNotes: "- budget!", transcript: full, meetingLanguage: "it")

        // Contesto minimo: tolti regole e risposta restano circa 4.000 token, meno della Trascrizione.
        let summary = try await Summarizer(client: client(stub), maxContextTokens: 8_192).summarize(prompt)

        let partials = stub.requests.count - 1
        #expect(partials > 1)
        #expect(summary == "riassunto \(partials + 1)")

        // Ogni paragrafo finisce in un solo blocco, nell'ordine originale.
        let sentParagraphs = (0..<partials).flatMap { index in
            stub.message(index, "user")!.components(separatedBy: "\n").filter { $0.hasPrefix("**[") }
        }
        #expect(sentParagraphs == full.markdown.components(separatedBy: "\n").filter { $0.hasPrefix("**[") })
        #expect(sentParagraphs.count == 40)

        // L'unione riceve Template, Note personali e i riassunti parziali in ordine.
        let merge = try #require(stub.message(partials, "user"))
        #expect(merge.contains("## Sintesi\n## Azioni"))
        #expect(merge.contains("- budget!"))
        let positions = (1...partials).map { merge.range(of: "riassunto \($0)")!.lowerBound }
        #expect(positions == positions.sorted())
    }

    @Test("se anche i riassunti parziali non entrano nel contesto si uniscono a gruppi, finché ci stanno")
    func hierarchicalMerge() async throws {
        // Ogni riassunto parziale è lungo: con 120 paragrafi e il contesto minimo l'unione diretta non entra.
        let longPartial = String(repeating: "dettaglio importante ", count: 150)
        let stub = StubTransport { _ in longPartial }
        let prompt = SummaryPrompt(template: template, personalNotes: "", transcript: transcript(paragraphs: 120), meetingLanguage: "it")

        _ = try await Summarizer(client: client(stub), maxContextTokens: 8_192).summarize(prompt)

        // Nessuna richiesta supera il contesto (stima: 3 caratteri per token, 4.096 riservati alla risposta).
        for index in stub.requests.indices {
            let characters = (stub.message(index, "system") ?? "").count + (stub.message(index, "user") ?? "").count
            #expect(characters / 3 + SummaryPrompt.replyReserveTokens <= 8_192, "richiesta \(index) troppo grande")
        }
        // Ci sono stati riassunti di gruppo (più delle sole parti + unione) e l'ultima richiesta è l'unione con il Template.
        #expect((0..<stub.requests.count).contains { stub.message($0, "system")?.contains("parti consecutive") == true })
        #expect(stub.message(stub.requests.count - 1, "user")?.contains("## Sintesi\n## Azioni") == true)
    }

    @Test("un contesto troppo piccolo viene portato al minimo utilizzabile")
    func minimumContext() async throws {
        let stub = StubTransport { _ in "ok" }
        let prompt = SummaryPrompt(template: template, personalNotes: "", transcript: transcript(paragraphs: 12), meetingLanguage: "it")

        _ = try await Summarizer(client: client(stub), maxContextTokens: 0).summarize(prompt)

        // Con il minimo (8.192 token) 12 paragrafi stanno in pochi blocchi, non uno per paragrafo.
        #expect(stub.requests.count < 6)
    }
}
