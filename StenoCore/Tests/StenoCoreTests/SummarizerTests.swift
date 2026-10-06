import Foundation
import Testing
import StenoCore

@Suite("Summary in one or more requests")
struct SummarizerTests {
    let template = Template(fileName: "Notes", content: "### Topics\n### Next steps")

    /// `count` paragraphs alternating Others/Me, each about 300 characters long.
    func transcript(paragraphs count: Int) -> Transcript {
        Transcript(utterances: (0..<count).map { index in
            Utterance(
                track: index.isMultiple(of: 2) ? .others : .me,
                start: Double(index * 20), end: Double(index * 20 + 15),
                text: "Paragraph \(index): " + String(repeating: "words from the meeting ", count: 13)
            )
        })
    }

    func client(_ stub: StubTransport) -> ChatClient {
        ChatClient(baseURL: URL(string: "https://x.example/v1")!, apiKey: nil, model: "m", transport: stub.send)
    }

    @Test("if the Transcript fits in the context one request is enough")
    func single() async throws {
        let stub = StubTransport { _ in "### Topics\nAll good." }
        let prompt = SummaryPrompt(template: template, personalNotes: "", transcript: transcript(paragraphs: 6), meetingLanguage: "it")

        let summary = try await Summarizer(client: client(stub), maxContextTokens: 32_000).summarize(prompt)

        #expect(summary == "### Topics\nAll good.")
        #expect(stub.requests.count == 1)
    }

    @Test("the times the model cites are removed from the Summary, the rest of the Markdown stays as it is")
    func citedTimesRemoved() async throws {
        let reply = """
            ### Topics
            - The budget is approved. [00:00]
              - Approved by the board [00:05] [01:10].
            - Rollout in two steps ([03:10], [1:02:45])
            - Long discussion [04:00-06:30]
            - Meeting at 10:30 on Friday, see [[Budget 2026]] and [the offer](https://x.example/offer)

            ### Next steps
            - [ ] Send the offer (Me) [00:05]
            - [x] Book the room
            """
        let stub = StubTransport { _ in reply }
        let prompt = SummaryPrompt(template: template, personalNotes: "", transcript: transcript(paragraphs: 6), meetingLanguage: "it")

        let summary = try await Summarizer(client: client(stub), maxContextTokens: 32_000).summarize(prompt)

        #expect(summary == """
            ### Topics
            - The budget is approved.
              - Approved by the board.
            - Rollout in two steps
            - Long discussion
            - Meeting at 10:30 on Friday, see [[Budget 2026]] and [the offer](https://x.example/offer)

            ### Next steps
            - [ ] Send the offer (Me)
            - [x] Book the room
            """)
    }

    @Test("in blocks the partial summaries keep their times for the merge, the final Summary loses them")
    func citedTimesInBlocks() async throws {
        let stub = StubTransport { index in "- point \(index + 1) [00:20]" }
        let prompt = SummaryPrompt(template: template, personalNotes: "", transcript: transcript(paragraphs: 40), meetingLanguage: "it")

        let summary = try await Summarizer(client: client(stub), maxContextTokens: 8_192).summarize(prompt)

        let merge = try #require(stub.message(stub.requests.count - 1, "user"))
        #expect(merge.contains("- point 1 [00:20]"))
        #expect(summary == "- point \(stub.requests.count)")
        // The last block may stop mid-sentence too.
        #expect(stub.message(0, "system")?.contains("The Transcript may stop mid-sentence") == true)
    }

    @Test("if it does not fit it is summarised in blocks, in order, and the partial summaries are merged with the Template")
    func chunked() async throws {
        let stub = StubTransport { index in "summary \(index + 1)" }
        let full = transcript(paragraphs: 40)
        let prompt = SummaryPrompt(template: template, personalNotes: "- budget!", transcript: full, meetingLanguage: "it")

        // Minimum context: after rules and reply about 4,000 tokens are left, less than the Transcript.
        let summary = try await Summarizer(client: client(stub), maxContextTokens: 8_192).summarize(prompt)

        let partials = stub.requests.count - 1
        #expect(partials > 1)
        #expect(summary == "summary \(partials + 1)")

        // Every paragraph ends up in exactly one block, in the original order.
        let sentParagraphs = (0..<partials).flatMap { index in
            stub.message(index, "user")!.components(separatedBy: "\n").filter { $0.hasPrefix("**[") }
        }
        #expect(sentParagraphs == full.markdown.components(separatedBy: "\n").filter { $0.hasPrefix("**[") })
        #expect(sentParagraphs.count == 40)

        // The merge gets the Template, the personal notes and the partial summaries in order.
        let merge = try #require(stub.message(partials, "user"))
        #expect(merge.contains("### Topics\n### Next steps"))
        #expect(merge.contains("- budget!"))
        let positions = (1...partials).map { merge.range(of: "summary \($0)")!.lowerBound }
        #expect(positions == positions.sorted())
    }

    @Test("if even the partial summaries do not fit, they are merged in groups until they do")
    func hierarchicalMerge() async throws {
        // Every partial summary is long: with 120 paragraphs and the minimum context a direct merge does not fit.
        let longPartial = String(repeating: "important detail ", count: 185)
        let stub = StubTransport { _ in longPartial }
        let prompt = SummaryPrompt(template: template, personalNotes: "", transcript: transcript(paragraphs: 120), meetingLanguage: "it")

        _ = try await Summarizer(client: client(stub), maxContextTokens: 8_192).summarize(prompt)

        // No request exceeds the context (estimate: 3 characters per token, 4,096 reserved for the reply).
        for index in stub.requests.indices {
            let characters = (stub.message(index, "system") ?? "").count + (stub.message(index, "user") ?? "").count
            #expect(characters / 3 + SummaryPrompt.replyReserveTokens <= 8_192, "request \(index) is too large")
        }
        // There were group summaries, and the last request is the merge with the Template.
        #expect((0..<stub.requests.count).contains { stub.message($0, "system")?.contains("consecutive parts") == true })
        #expect(stub.message(stub.requests.count - 1, "user")?.contains("### Topics\n### Next steps") == true)
    }

    @Test("the Vocabulary is in every request: blocks, groups and the final merge, all within the context")
    func vocabularyInEveryRequest() async throws {
        let longPartial = String(repeating: "important detail ", count: 185)
        let stub = StubTransport { _ in longPartial }
        let prompt = SummaryPrompt(
            template: template, personalNotes: "", transcript: transcript(paragraphs: 120), meetingLanguage: "it",
            vocabulary: Vocabulary(fileContent: "- Scaleway = scale uai | our EU cloud provider\n- Mameli")
        )

        _ = try await Summarizer(client: client(stub), maxContextTokens: 8_192).summarize(prompt)

        #expect(stub.requests.count > 3)
        for index in stub.requests.indices {
            let system = try #require(stub.message(index, "system"))
            #expect(system.contains("- Scaleway: our EU cloud provider (may be written as \"scale uai\")"), "request \(index)")
            #expect(system.contains("- Mameli"), "request \(index)")
            let characters = system.count + (stub.message(index, "user") ?? "").count
            #expect(characters / 3 + SummaryPrompt.replyReserveTokens <= 8_192, "request \(index) is too large")
        }
    }

    @Test("a context that is too small is raised to the usable minimum")
    func minimumContext() async throws {
        let stub = StubTransport { _ in "ok" }
        let prompt = SummaryPrompt(template: template, personalNotes: "", transcript: transcript(paragraphs: 12), meetingLanguage: "it")

        _ = try await Summarizer(client: client(stub), maxContextTokens: 0).summarize(prompt)

        // With the minimum (8,192 tokens) 12 paragraphs fit in a few blocks, not one per paragraph.
        #expect(stub.requests.count < 6)
    }
}
