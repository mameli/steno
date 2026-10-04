import Testing
import StenoCore

@Suite("Template del Riepilogo")
struct TemplateTests {
    @Test("dal file si leggono nome, lingua del Riepilogo e corpo")
    func parse() {
        let template = Template(fileName: "1-1 settimanale", content: """
            ---
            nome: 1:1 settimanale
            lingua_riepilogo: it
            ---
            Concentrati su blocchi e decisioni.

            ## Punti discussi
            ## Azioni
            """)

        #expect(template.name == "1:1 settimanale")
        #expect(template.summaryLanguage == "it")
        #expect(template.body == "Concentrati su blocchi e decisioni.\n\n## Punti discussi\n## Azioni")
    }

    @Test("senza frontmatter il nome è quello del file e la lingua segue la Riunione")
    func withoutFrontmatter() {
        let template = Template(fileName: "Retro", content: "## Cosa è andato bene\n## Cosa migliorare\n")

        #expect(template.name == "Retro")
        #expect(template.summaryLanguage == nil)
        #expect(template.body == "## Cosa è andato bene\n## Cosa migliorare")
    }

    @Test("lingua_riepilogo auto o sconosciuta vuol dire: la lingua della Riunione", arguments: ["auto", "fr", ""])
    func automaticLanguage(value: String) {
        let template = Template(fileName: "T", content: "---\nlingua_riepilogo: \(value)\n---\nCorpo")

        #expect(template.summaryLanguage == nil)
    }

    @Test("il Template Generico creato da Steno ha le sezioni concordate")
    func generic() {
        let template = Template(fileName: "Generico", content: Template.genericFileContent)

        #expect(template.name == "Generico")
        #expect(template.summaryLanguage == nil)
        #expect(template.body == """
            Riassumi la riunione per chi c'era ma vuole ritrovare in fretta cosa conta.

            ## Sintesi
            ## Punti discussi
            ## Decisioni
            ## Azioni
            ## Domande aperte
            """)
    }

    @Test("un Template nuovo parte dal Generico con il nome scelto")
    func newTemplate() {
        let template = Template(fileName: "Retro sprint", content: Template.newFileContent(name: "Retro sprint"))
        let generic = Template(fileName: Template.genericName, content: Template.genericFileContent)

        #expect(template.name == "Retro sprint")
        #expect(template.summaryLanguage == nil)
        #expect(template.body == generic.body)
    }
}
