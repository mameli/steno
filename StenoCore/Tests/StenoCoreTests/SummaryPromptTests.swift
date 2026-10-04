import Testing
import StenoCore

@Suite("Prompt del Riepilogo")
struct SummaryPromptTests {
    let template = Template(fileName: "Generico", content: "Sii breve.\n\n## Sintesi\n## Azioni")
    let transcript = Transcript(utterances: [
        Utterance(track: .others, start: 0, end: 4, text: "Il budget è approvato."),
        Utterance(track: .me, start: 5, end: 8, text: "Mando io l'offerta venerdì."),
    ])

    @Test("il messaggio utente contiene Template, Note personali e Trascrizione, in quest'ordine")
    func userMessage() {
        let prompt = SummaryPrompt(template: template, personalNotes: "- budget!", transcript: transcript, meetingLanguage: "it")

        let messages = prompt.singleRequest()

        #expect(messages.map(\.role) == [.system, .user])
        #expect(messages[1].content == """
            # Template
            Sii breve.

            ## Sintesi
            ## Azioni

            # Note personali
            - budget!

            # Trascrizione
            **[00:00] Altri:** Il budget è approvato.

            **[00:05] Io:** Mando io l'offerta venerdì.
            """)
    }

    @Test("le regole stanno nel messaggio di sistema")
    func systemRules() {
        let system = SummaryPrompt(template: template, personalNotes: "", transcript: transcript, meetingLanguage: "it")
            .singleRequest()[0].content

        #expect(system.contains("Scrivi in italiano."))
        #expect(system.contains("Non inventare"))
        #expect(system.contains("Segui la struttura e le istruzioni del Template"))
        // Il formato delle azioni lo decide il Template; questo vale solo se il Template non dice niente.
        #expect(system.contains("nel formato indicato dal Template"))
        #expect(system.contains("- [ ] chi: cosa (quando)"))
        #expect(system.contains("\"Io\""))
        #expect(system.contains("Note personali"))
    }

    @Test("lingua del Riepilogo: quella del Template, altrimenti della Riunione, altrimenti italiano", arguments: [
        ("en", "it", "Scrivi in inglese."),
        (nil, "en", "Scrivi in inglese."),
        (nil, "it", "Scrivi in italiano."),
        (nil, nil, "Scrivi in italiano."),
        ("it", "en", "Scrivi in italiano."),
    ] as [(String?, String?, String)])
    func language(templateLanguage: String?, meetingLanguage: String?, rule: String) {
        let header = templateLanguage.map { "---\nlingua_riepilogo: \($0)\n---\n" } ?? ""
        let template = Template(fileName: "T", content: header + "## Sintesi")

        let system = SummaryPrompt(template: template, personalNotes: "", transcript: transcript, meetingLanguage: meetingLanguage)
            .singleRequest()[0].content

        #expect(system.contains(rule))
    }

    @Test("senza Note personali il modello lo sa esplicitamente")
    func noPersonalNotes() {
        let user = SummaryPrompt(template: template, personalNotes: "", transcript: transcript, meetingLanguage: "it")
            .singleRequest()[1].content

        #expect(user.contains("# Note personali\n(nessuna)\n"))
    }
}
