import Testing
import StenoCore

@Suite("Summary prompt")
struct SummaryPromptTests {
    let template = Template(fileName: "Notes", content: "Be brief.\n\n### Topics\n### Next steps")
    let transcript = Transcript(utterances: [
        Utterance(track: .others, start: 0, end: 4, text: "The budget is approved."),
        Utterance(track: .me, start: 5, end: 8, text: "I'll send the offer on Friday."),
    ])

    @Test("the user message holds Template, personal notes and Transcript, in this order")
    func userMessage() {
        let prompt = SummaryPrompt(template: template, personalNotes: "- budget!", transcript: transcript, meetingLanguage: "it")

        let messages = prompt.singleRequest()

        #expect(messages.map(\.role) == [.system, .user])
        #expect(messages[1].content == """
            # Template
            Be brief.

            ### Topics
            ### Next steps

            # Personal notes
            - budget!

            # Transcript
            **[00:00] Others:** The budget is approved.

            **[00:05] Me:** I'll send the offer on Friday.
            """)
    }

    @Test("the rules live in the system message")
    func systemRules() {
        let system = SummaryPrompt(template: template, personalNotes: "", transcript: transcript, meetingLanguage: "it")
            .singleRequest()[0].content

        #expect(system.contains("Write the summary in Italian"))
        #expect(system.contains("Do not invent"))
        #expect(system.contains("Follow the structure and instructions of the Template"))
        // The action format is the Template's; this one applies only when the Template says nothing.
        #expect(system.contains("in the format the Template asks for"))
        #expect(system.contains("- [ ] who: what (when)"))
        #expect(system.contains("\"Me\""))
        #expect(system.contains("personal notes"))
    }

    @Test("Summary language: the Template's, else the Meeting's, else Italian; any language can be named", arguments: [
        ("en", "it", "Write the summary in English"),
        (nil, "en", "Write the summary in English"),
        (nil, "it", "Write the summary in Italian"),
        (nil, nil, "Write the summary in Italian"),
        ("fr", "en", "Write the summary in French"),
        ("de", nil, "Write the summary in German"),
    ] as [(String?, String?, String)])
    func language(templateLanguage: String?, meetingLanguage: String?, rule: String) {
        let header = templateLanguage.map { "---\nsummary_language: \($0)\n---\n" } ?? ""
        let template = Template(fileName: "T", content: header + "### Topics")

        let system = SummaryPrompt(template: template, personalNotes: "", transcript: transcript, meetingLanguage: meetingLanguage)
            .singleRequest()[0].content

        #expect(system.contains(rule))
    }

    @Test("without personal notes the model is told so explicitly")
    func noPersonalNotes() {
        let user = SummaryPrompt(template: template, personalNotes: "", transcript: transcript, meetingLanguage: "it")
            .singleRequest()[1].content

        #expect(user.contains("# Personal notes\n(none)\n"))
    }
}
