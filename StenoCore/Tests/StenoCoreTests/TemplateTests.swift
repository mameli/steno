import Testing
import StenoCore

@Suite("Summary Template")
struct TemplateTests {
    @Test("the file gives name, Summary language and body")
    func parse() {
        let template = Template(fileName: "1-1 weekly", content: """
            ---
            name: 1:1 weekly
            summary_language: it
            ---
            Focus on blockers and decisions.

            ### Topics
            ### Next steps
            """)

        #expect(template.name == "1:1 weekly")
        #expect(template.summaryLanguage == "it")
        #expect(template.body == "Focus on blockers and decisions.\n\n### Topics\n### Next steps")
    }

    @Test("without frontmatter the name is the file's and the language follows the Meeting")
    func withoutFrontmatter() {
        let template = Template(fileName: "Retro", content: "### What went well\n### What to improve\n")

        #expect(template.name == "Retro")
        #expect(template.summaryLanguage == nil)
        #expect(template.body == "### What went well\n### What to improve")
    }

    @Test("summary_language accepts any language code; auto or empty means the Meeting's language", arguments: [
        ("fr", "fr"),
        ("DE", "de"),
        ("pt-BR", "pt-br"),
        ("auto", nil),
        ("", nil),
        ("not a language", nil),
    ] as [(String, String?)])
    func language(value: String, expected: String?) {
        let template = Template(fileName: "T", content: "---\nsummary_language: \(value)\n---\nBody")

        #expect(template.summaryLanguage == expected)
    }

    @Test("Templates written before the English rewrite (nome, lingua_riepilogo) still work")
    func legacyKeys() {
        let template = Template(fileName: "Vecchio", content: "---\nnome: Settimanale\nlingua_riepilogo: en\n---\nCorpo")

        #expect(template.name == "Settimanale")
        #expect(template.summaryLanguage == "en")
    }

    @Test("the default Notes Template asks for topics in Meeting order and Next steps at the end")
    func defaultTemplate() {
        let template = Template(fileName: "Notes", content: Template.defaultFileContent)

        #expect(template.name == "Notes")
        #expect(template.summaryLanguage == nil)
        #expect(template.body.contains("in the order they were discussed"))
        #expect(template.body.contains("### Next steps"))
        #expect(template.body.contains("- [ ] What to do (Who)"))
    }

    @Test("a new Template starts from the default one with the chosen name")
    func newTemplate() {
        let template = Template(fileName: "Sprint retro", content: Template.newFileContent(name: "Sprint retro"))
        let base = Template(fileName: Template.defaultName, content: Template.defaultFileContent)

        #expect(template.name == "Sprint retro")
        #expect(template.summaryLanguage == nil)
        #expect(template.body == base.body)
    }

    @Test("the Italian default Template of earlier versions is recognised, so it can be replaced")
    func legacyDefault() {
        #expect(Template.isLegacyDefault(Template.legacyDefaultFileContent))
        #expect(!Template.isLegacyDefault(Template.defaultFileContent))
        #expect(!Template.isLegacyDefault(Template.legacyDefaultFileContent + "\nMy own extra rule."))
    }

    @Test("the Italian default exactly as the previous version wrote it to the Vault is recognised")
    func legacyDefaultAsWritten() {
        let writtenByPreviousVersion = """
            ---
            nome: Appunti
            lingua_riepilogo: auto
            ---
            Scrivi gli appunti della riunione come li prenderebbe un collega attento, non un verbale.

            - Dividi la riunione in argomenti, nell'ordine in cui sono stati discussi. Per ogni argomento un'intestazione `###` con un titolo breve e concreto.
            - Sotto ogni argomento un elenco puntato: un punto per ogni idea, proposta, decisione o problema, con sotto-punti per motivi, dettagli, persone, cifre, date e link. Frasi brevi, niente premesse.
            - Le decisioni stanno nell'argomento a cui appartengono, non in una sezione a parte.
            - Niente sintesi iniziale e niente conclusioni generiche.

            ### Prossimi passi
            Un punto per ogni azione concordata, nella forma `- [ ] Cosa fare (Chi)`, con sotto un sotto-punto per contesto e scadenza quando ci sono.

            """

        #expect(Template.isLegacyDefault(writtenByPreviousVersion))
    }

    @Test("the default Templates contain no stray backslashes from line continuations")
    func noStrayBackslashes() {
        #expect(!Template.defaultFileContent.contains("\\"))
        #expect(!Template.legacyDefaultFileContent.contains("\\"))
    }
}
