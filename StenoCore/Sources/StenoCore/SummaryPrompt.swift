import Foundation

/// Cosa Steno chiede al modello per scrivere il Riepilogo di una Riunione.
public struct SummaryPrompt: Sendable {
    private let template: Template
    private let personalNotes: String
    private let transcript: Transcript
    private let meetingLanguage: String?

    public init(template: Template, personalNotes: String, transcript: Transcript, meetingLanguage: String?) {
        self.template = template
        self.personalNotes = personalNotes
        self.transcript = transcript
        self.meetingLanguage = meetingLanguage
    }

    /// `it` o `en`: quella del Template, altrimenti della Riunione, altrimenti italiano.
    public var summaryLanguage: String {
        template.summaryLanguage ?? meetingLanguage ?? "it"
    }

    /// Una sola richiesta con tutta la Trascrizione.
    public func singleRequest() -> [ChatMessage] {
        [
            ChatMessage(role: .system, content: systemRules),
            ChatMessage(role: .user, content: """
                \(templateAndNotes)

                # Trascrizione
                \(transcript.markdown.trimmingCharacters(in: .newlines))
                """),
        ]
    }

    /// Spazio lasciato alla risposta del modello in ogni richiesta.
    public static let replyReserveTokens = 4_096

    /// Stima prudente: circa 3 caratteri per token (l'italiano ne usa più dell'inglese).
    static func estimatedTokens(_ messages: [ChatMessage]) -> Int {
        messages.reduce(0) { $0 + $1.content.count / 3 + 4 }
    }

    func fits(maxContextTokens: Int) -> Bool {
        Self.estimatedTokens(singleRequest()) + Self.replyReserveTokens <= maxContextTokens
    }

    /// La Trascrizione divisa in blocchi di paragrafi consecutivi, una richiesta per blocco.
    /// Un paragrafo non viene mai spezzato: se da solo supera lo spazio, forma un blocco.
    func partialRequests(maxContextTokens: Int) -> [[ChatMessage]] {
        let overhead = Self.estimatedTokens(partialRequest(part: 1, of: 1, transcript: ""))
        let budget = max(1, (maxContextTokens - Self.replyReserveTokens - overhead) * 3)

        var blocks: [[Paragraph]] = []
        var size = 0
        for paragraph in transcript.paragraphs {
            let length = Transcript.markdown(of: [paragraph]).count + 1
            if blocks.isEmpty || size + length > budget {
                blocks.append([])
                size = 0
            }
            blocks[blocks.count - 1].append(paragraph)
            size += length
        }
        return blocks.enumerated().map { index, block in
            partialRequest(
                part: index + 1, of: blocks.count,
                transcript: Transcript.markdown(of: block).trimmingCharacters(in: .newlines)
            )
        }
    }

    func mergeFits(partials: [String], maxContextTokens: Int) -> Bool {
        Self.estimatedTokens(mergeRequest(partials: partials)) + Self.replyReserveTokens <= maxContextTokens
    }

    /// Quando l'unione non entra nel contesto: i riassunti parziali consecutivi si raggruppano
    /// e ogni gruppo diventa un riassunto solo, con una richiesta per gruppo.
    func groupRequests(partials: [String], maxContextTokens: Int) -> [[ChatMessage]] {
        let overhead = Self.estimatedTokens(groupRequest(""))
        let budget = max(1, (maxContextTokens - Self.replyReserveTokens - overhead) * 3)
        var groups: [[String]] = []
        var size = 0
        for partial in partials {
            if groups.isEmpty || size + partial.count + 2 > budget {
                groups.append([])
                size = 0
            }
            groups[groups.count - 1].append(partial)
            size += partial.count + 2
        }
        return groups.map { groupRequest($0.joined(separator: "\n\n")) }
    }

    private func groupRequest(_ partials: String) -> [ChatMessage] {
        [
            ChatMessage(role: .system, content: """
                Sei Steno. Ricevi i riassunti di parti consecutive della stessa riunione.
                Uniscili in un unico riassunto fedele e compatto, in \(languageName): argomenti, decisioni, azioni (chi, cosa, quando) e domande aperte, con i timestamp.
                Non inventare. Rispondi solo con il riassunto.
                """),
            ChatMessage(role: .user, content: """
                # Note personali
                \(notesOrNone)

                # Riassunti di parti consecutive
                \(partials)
                """),
        ]
    }

    /// Unisce i riassunti parziali in un Riepilogo che segue il Template.
    func mergeRequest(partials: [String]) -> [ChatMessage] {
        let parts = partials.enumerated()
            .map { "Parte \($0.offset + 1) di \(partials.count):\n\($0.element)" }
            .joined(separator: "\n\n")
        return [
            ChatMessage(role: .system, content: systemRules),
            ChatMessage(role: .user, content: """
                \(templateAndNotes)

                # Trascrizione
                La Trascrizione era troppo lunga per una sola richiesta: qui sotto ci sono i riassunti delle sue parti, in ordine.

                \(parts)
                """),
        ]
    }

    private func partialRequest(part: Int, of count: Int, transcript: String) -> [ChatMessage] {
        [
            ChatMessage(role: .system, content: """
                Sei Steno. Ricevi la parte \(part) di \(count) della Trascrizione di una riunione.
                Riassumila in modo fedele e compatto, in \(languageName): argomenti, decisioni, azioni (chi, cosa, quando) e domande aperte, con i timestamp.
                Nella Trascrizione "Io" è chi ha preso le Note personali, "Altri" sono gli altri partecipanti.
                Non inventare. Rispondi solo con il riassunto.
                """),
            ChatMessage(role: .user, content: """
                # Note personali
                \(notesOrNone)

                # Trascrizione, parte \(part) di \(count)
                \(transcript)
                """),
        ]
    }

    private var templateAndNotes: String {
        """
        # Template
        \(template.body)

        # Note personali
        \(notesOrNone)
        """
    }

    private var notesOrNone: String {
        personalNotes.isEmpty ? "(nessuna)" : personalNotes
    }

    private var languageName: String {
        StenoCore.languageName(summaryLanguage)
    }

    private var systemRules: String {
        """
        Sei Steno e scrivi il Riepilogo di una riunione a partire dalla sua Trascrizione.

        Regole:
        - Scrivi in \(languageName).
        - Segui il Template: usa le sue intestazioni, nello stesso ordine, e rispetta le sue istruzioni.
        - Non inventare: usa solo quello che c'è nella Trascrizione e nelle Note personali.
        - Nella Trascrizione "Io" è chi ha preso le Note personali, "Altri" sono gli altri partecipanti, senza distinguerli.
        - Le Note personali dicono cosa conta per chi le ha scritte: dai la precedenza a quei temi.
        - Scrivi le azioni come `- [ ] chi: cosa (quando)`; se chi o quando non sono chiari, ometti quella parte.
        - Rispondi solo con il Riepilogo in Markdown, senza preamboli.
        """
    }
}

/// Nome della lingua da usare nelle istruzioni al modello (scritte in italiano).
func languageName(_ code: String) -> String {
    code == "en" ? "inglese" : "italiano"
}
