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

    @Test("il Template predefinito Appunti chiede argomenti nell'ordine della Riunione e Prossimi passi in fondo")
    func defaultTemplate() {
        let template = Template(fileName: "Appunti", content: Template.defaultFileContent)

        #expect(template.name == "Appunti")
        #expect(template.summaryLanguage == nil)
        #expect(template.body.contains("nell'ordine in cui sono stati discussi"))
        #expect(template.body.contains("### Prossimi passi"))
        #expect(template.body.contains("- [ ] Cosa fare (Chi)"))
        #expect(!template.body.contains("## Sintesi"))
    }

    @Test("un Template nuovo parte dal predefinito con il nome scelto")
    func newTemplate() {
        let template = Template(fileName: "Retro sprint", content: Template.newFileContent(name: "Retro sprint"))
        let base = Template(fileName: Template.defaultName, content: Template.defaultFileContent)

        #expect(template.name == "Retro sprint")
        #expect(template.summaryLanguage == nil)
        #expect(template.body == base.body)
    }
}
