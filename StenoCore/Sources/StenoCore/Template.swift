import Foundation

/// Un file nel Vault che definisce struttura e istruzioni del Riepilogo per un tipo di Riunione.
public struct Template: Equatable, Sendable {
    public let name: String
    /// `it` o `en` per forzare la lingua del Riepilogo, `nil` per usare quella della Riunione.
    public let summaryLanguage: String?
    /// Istruzioni libere e struttura a intestazioni, passate al modello così come sono.
    public let body: String

    /// Il Template che Steno crea nel Vault quando la cartella dei Template è vuota.
    public static let genericName = "Generico"
    public static let genericFileContent = """
        ---
        nome: Generico
        lingua_riepilogo: auto
        ---
        Riassumi la riunione per chi c'era ma vuole ritrovare in fretta cosa conta.

        ## Sintesi
        ## Punti discussi
        ## Decisioni
        ## Azioni
        ## Domande aperte

        """

    /// Il contenuto di un Template nuovo creato dall'utente: il Generico con il nome scelto.
    public static func newFileContent(name: String) -> String {
        genericFileContent.replacingOccurrences(of: "nome: \(genericName)", with: "nome: \(name)")
    }

    public init(fileName: String, content: String) {
        let (values, body) = Self.splitFrontmatter(content)
        name = values["nome"].flatMap { $0.isEmpty ? nil : $0 } ?? fileName
        summaryLanguage = values["lingua_riepilogo"].flatMap { ["it", "en"].contains($0) ? $0 : nil }
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Chiavi semplici `chiave: valore` del frontmatter e corpo che segue.
    private static func splitFrontmatter(_ content: String) -> ([String: String], String) {
        let lines = MeetingNote(content: content).content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let close = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespaces) == "---" })
        else { return ([:], lines.joined(separator: "\n")) }

        var values: [String: String] = [:]
        for line in lines[1..<close] {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            values[String(line[..<colon])] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return (values, lines[(close + 1)...].joined(separator: "\n"))
    }
}
