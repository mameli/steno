import Foundation

/// Il titolo breve di una Riunione, generato dal modello a partire dal Riepilogo.
public enum MeetingTitle {
    public static let maxWords = 6

    public static func request(summary: String, language: String) -> [ChatMessage] {
        [
            ChatMessage(role: .system, content: """
                Scrivi il titolo di una riunione a partire dal suo Riepilogo: al massimo \(maxWords) parole, \
                in \(languageName(language)), senza data, senza virgolette e senza punto finale. \
                Rispondi solo con il titolo.
                """),
            ChatMessage(role: .user, content: summary),
        ]
    }

    /// Prima riga con parole, senza intestazioni Markdown, prefissi "Titolo:", virgolette,
    /// grassetto e punteggiatura finale, al massimo `maxWords` parole. `nil` se non resta niente.
    public static func clean(_ reply: String) -> String? {
        guard var line = reply.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return nil }

        // Intestazioni, grassetto, virgolette e prefissi possono comparire in qualsiasi ordine
        // ("**Titolo:** …", "## Titolo: \"…\""): si tolgono finché qualcosa cambia.
        let wrapping = CharacterSet(charactersIn: "#\"'“”‘’«»*_`").union(.whitespaces)
        var previous = ""
        while line != previous {
            previous = line
            line = line.trimmingCharacters(in: wrapping)
            for prefix in ["titolo:", "title:"] where line.lowercased().hasPrefix(prefix) {
                line.removeFirst(prefix.count)
            }
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: ".!;:,").union(wrapping))
        }

        let words = line.split(whereSeparator: \.isWhitespace).prefix(maxWords)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}
