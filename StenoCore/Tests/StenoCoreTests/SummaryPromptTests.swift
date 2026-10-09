import Testing
@testable import StenoCore

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

    @Test("Me is written with the user's name, also in the partial requests of a long Meeting")
    func meByName() {
        let prompt = SummaryPrompt(
            template: template, personalNotes: "", transcript: transcript, meetingLanguage: "it", userName: " Mario Rossi "
        )

        #expect(prompt.singleRequest()[0].content.contains("\"Me\" is Mario Rossi, the person who took the personal notes"))
        #expect(prompt.singleRequest()[0].content.contains("never as \"Me\""))
        #expect(prompt.partialRequests(maxContextTokens: 8_192)[0][0].content.contains("\"Me\" is Mario Rossi"))
    }

    @Test("without the user's name the model still never writes Me")
    func meWithoutName() {
        let system = SummaryPrompt(template: template, personalNotes: "", transcript: transcript, meetingLanguage: "it", userName: "")
            .singleRequest()[0].content

        #expect(system.contains("Never write \"Me\" in the summary"))
    }

    @Test("the model names a Speaker from what is said, writes the number only on an action, and leaves no placeholder for who")
    func speakers() {
        let system = SummaryPrompt(template: template, personalNotes: "", transcript: transcript, meetingLanguage: "it")
            .singleRequest()[0].content

        #expect(system.contains("\"Speaker 1\", \"Speaker 2\"…, told apart by their voice"))
        #expect(system.contains("the one they introduce themselves with, or the one they answer to when called"))
        #expect(system.contains("write \"Speaker N\" only as who takes on an action"))
        #expect(system.contains("never \"Speaker N\" in a heading or in the other bullets"))
        #expect(system.contains("Leave out who or when if they are not clear, with nothing in their place"))
    }

    @Test("every point must cite the time of the Transcript it comes from, and the model knows the times are removed")
    func citedTimes() {
        let system = SummaryPrompt(template: template, personalNotes: "", transcript: transcript, meetingLanguage: "it")
            .singleRequest()[0].content

        #expect(system.contains("end it with the time of the Transcript passage it comes from"))
        #expect(system.contains("`[12:34]`"))
        #expect(system.contains("Leave out what you cannot point to"))
        #expect(system.contains("Steno removes the times"))
    }

    @Test("a Transcript cut mid-sentence is summarised only up to where it stops")
    func truncatedTranscript() {
        let system = SummaryPrompt(template: template, personalNotes: "", transcript: transcript, meetingLanguage: "it")
            .singleRequest()[0].content

        #expect(system.contains("The Transcript may stop mid-sentence"))
        #expect(system.contains("do not complete talks, lists, steps or results that are announced but not reached"))
    }

    let vocabulary = Vocabulary(fileContent: """
        - Steno = absteno, steno | our app for recording meetings
        - Scaleway = scale uai
        - Mameli
        """)

    @Test("the Vocabulary goes into the system message, with the rule to correct only what is certain")
    func vocabularyInSystemMessage() {
        let messages = SummaryPrompt(
            template: template, personalNotes: "", transcript: transcript, meetingLanguage: "it", vocabulary: vocabulary
        ).singleRequest()

        let system = messages[0].content
        #expect(system.contains("- Steno: our app for recording meetings (may be written as \"absteno\", \"steno\")"))
        #expect(system.contains("- Scaleway (may be written as \"scale uai\")"))
        #expect(system.contains("\n- Mameli\n"))
        #expect(system.contains("automatic speech recognition"))
        #expect(system.contains("only when you are sure"))
        // The Vocabulary is not part of what the user message carries.
        #expect(!messages[1].content.contains("Scaleway"))
    }

    @Test("without a Vocabulary the system message has no trace of it")
    func noVocabulary() {
        let system = SummaryPrompt(template: template, personalNotes: "", transcript: transcript, meetingLanguage: "it")
            .singleRequest()[0].content

        #expect(!system.contains("Vocabulary"))
        #expect(system.hasSuffix("without preambles."))
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

@Suite("Summary prompt: Speaker names")
struct SummaryPromptPeopleTests {
    let template = Template(fileName: "Notes", content: "Be brief.")
    let transcript = Transcript(utterances: [
        Utterance(track: .others, start: 0, end: 4, text: "The budget is approved.", speaker: 1),
        Utterance(track: .me, start: 5, end: 8, text: "I'll send the offer on Friday."),
    ])

    @Test("Speakers the user named are certain for the model; without names the rule is not there")
    func namedSpeakers() {
        let named = SummaryPrompt(
            template: template, personalNotes: "", transcript: transcript.naming([1: "Anna Bianchi"]), meetingLanguage: "it"
        )
        let unnamed = SummaryPrompt(template: template, personalNotes: "", transcript: transcript, meetingLanguage: "it")

        #expect(named.singleRequest()[0].content.contains("\"Name (Speaker N)\" in the Transcript is a name the user gave"))
        #expect(named.partialRequests(maxContextTokens: 8_192)[0][0].content.contains("\"Name (Speaker N)\""))
        #expect(named.singleRequest()[1].content.contains("**[00:00] Anna Bianchi (Speaker 1):**"))
        #expect(!unnamed.singleRequest()[0].content.contains("Name (Speaker N)"))
    }
}
