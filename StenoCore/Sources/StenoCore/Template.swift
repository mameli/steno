import Foundation

/// A file in the Vault that defines the structure and instructions of the Summary for a kind of Meeting.
public struct Template: Equatable, Sendable {
    public let name: String
    /// Language code that forces the Summary language (`it`, `en`, `fr`…), `nil` to use the Meeting's.
    public let summaryLanguage: String?
    /// Free-form instructions and structure, passed to the model as they are.
    public let body: String

    /// The Template Steno creates in the Vault when the Templates folder is empty: notes by
    /// topic, in Meeting order, and Next steps at the end (like Granola).
    public static let defaultName = "Notes"
    public static let defaultFileContent = """
        ---
        name: Notes
        summary_language: auto
        ---
        Write the meeting notes the way an attentive colleague would take them, not as formal minutes.

        - Split the meeting into topics, in the order they were discussed. For each topic \
        a `###` heading with a short, concrete title.
        - Under each topic a bullet list: one bullet per idea, proposal, decision or problem, \
        with sub-bullets for reasons, details, people, figures, dates and links. Short sentences, no preambles.
        - Decisions go in the topic they belong to, not in a separate section.
        - No opening summary and no generic conclusions.

        ### Next steps
        One bullet per agreed action, in the form `- [ ] What to do (Who)`, with a sub-bullet \
        for context and deadline when there are any.

        """

    /// The Italian default Template created before the English rewrite: if a Vault still has it
    /// untouched, Steno replaces it with the English one.
    public static let legacyDefaultFileContent = """
        ---
        nome: Appunti
        lingua_riepilogo: auto
        ---
        Scrivi gli appunti della riunione come li prenderebbe un collega attento, non un verbale.

        - Dividi la riunione in argomenti, nell'ordine in cui sono stati discussi. Per ogni argomento \
        un'intestazione `###` con un titolo breve e concreto.
        - Sotto ogni argomento un elenco puntato: un punto per ogni idea, proposta, decisione o problema, \
        con sotto-punti per motivi, dettagli, persone, cifre, date e link. Frasi brevi, niente premesse.
        - Le decisioni stanno nell'argomento a cui appartengono, non in una sezione a parte.
        - Niente sintesi iniziale e niente conclusioni generiche.

        ### Prossimi passi
        Un punto per ogni azione concordata, nella forma `- [ ] Cosa fare (Chi)`, con sotto un \
        sotto-punto per contesto e scadenza quando ci sono.

        """
    public static let legacyDefaultName = "Appunti"

    /// Whether a Template file is the untouched Italian default of earlier versions.
    public static func isLegacyDefault(_ content: String) -> Bool {
        MarkdownLines(content).text.trimmingCharacters(in: .whitespacesAndNewlines)
            == legacyDefaultFileContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The content of a new Template created by the user: the default one with the chosen name.
    public static func newFileContent(name: String) -> String {
        defaultFileContent.replacingOccurrences(of: "name: \(defaultName)", with: "name: \(name)")
    }

    public init(fileName: String, content: String) {
        let markdown = MarkdownLines(content)
        // Templates written before the English rewrite use `nome` and `lingua_riepilogo`.
        name = markdown.value("name", "nome").flatMap { $0.isEmpty ? nil : $0 } ?? fileName
        summaryLanguage = markdown.value("summary_language", "lingua_riepilogo").flatMap(Language.code)
        body = markdown.lines[markdown.bodyStart...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
