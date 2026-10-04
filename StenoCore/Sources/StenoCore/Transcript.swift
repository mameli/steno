import Foundation

/// Un tratto di parlato riconosciuto in una Traccia. Tempi in secondi dall'inizio della Riunione.
public struct Utterance: Codable, Equatable, Sendable {
    public let track: Track
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(track: Track, start: TimeInterval, end: TimeInterval, text: String) {
        self.track = track
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Battute consecutive della stessa Traccia, mostrate con un solo timestamp.
public struct Paragraph: Equatable, Sendable {
    public let track: Track
    public let start: TimeInterval
    public let text: String

    public init(track: Track, start: TimeInterval, text: String) {
        self.track = track
        self.start = start
        self.text = text
    }
}

/// Il testo parlato di una Riunione, con le due Tracce fuse in ordine di tempo.
public struct Transcript: Sendable {
    /// Oltre questa pausa la stessa Traccia riparte con un nuovo paragrafo e un nuovo timestamp.
    public static let paragraphBreak: TimeInterval = 30
    /// Una Battuta che inizia oltre questo tempo dall'inizio del paragrafo ne apre uno nuovo,
    /// così anche un monologo lungo ha un timestamp almeno ogni minuto.
    public static let maxParagraphDuration: TimeInterval = 60

    public let paragraphs: [Paragraph]

    public init(utterances: [Utterance]) {
        var paragraphs: [Paragraph] = []
        var lastEnd: TimeInterval = 0
        let spoken = utterances.compactMap { utterance -> Utterance? in
            let text = utterance.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !Self.isAnnotation(text) else { return nil }
            return Utterance(track: utterance.track, start: utterance.start, end: utterance.end, text: text)
        }
        for utterance in spoken.sorted(by: { $0.start < $1.start }) {
            defer { lastEnd = utterance.end }
            if let last = paragraphs.last, last.track == utterance.track,
               utterance.start - lastEnd <= Self.paragraphBreak,
               utterance.start - last.start < Self.maxParagraphDuration {
                paragraphs[paragraphs.count - 1] = Paragraph(
                    track: last.track, start: last.start, text: last.text + " " + utterance.text
                )
            } else {
                paragraphs.append(Paragraph(track: utterance.track, start: utterance.start, text: utterance.text))
            }
        }
        self.paragraphs = paragraphs
    }

    /// Corpo del file Trascrizione: `**[mm:ss] Io:** testo`, un paragrafo per blocco.
    public var markdown: String {
        Self.markdown(of: paragraphs)
    }

    static func markdown(of paragraphs: [Paragraph]) -> String {
        paragraphs
            .map { "**[\(elapsedLabel($0.start))] \($0.track.label):** \($0.text)\n" }
            .joined(separator: "\n")
    }

    /// Il file della Trascrizione nel Vault: frontmatter con il collegamento alla Nota della Riunione.
    /// `language` è `nil` se nella Riunione non si è sentito parlato.
    public func vaultFile(stenoID: UUID, meetingNoteName: String, language: String?) -> String {
        var frontmatter = ["---", "steno_id: \(stenoID.uuidString)", "riunione: \(MeetingNote.wikiLink(meetingNoteName))"]
        if let language { frontmatter.append("lingua: \(language)") }
        frontmatter.append("---")
        return frontmatter.joined(separator: "\n") + "\n" + markdown
    }

    /// Whisper descrive il non parlato tra parentesi: `[BLANK_AUDIO]`, `[Musica]`,
    /// e sul silenzio inventa intere frasi tra parentesi tonde.
    private static func isAnnotation(_ text: String) -> Bool {
        (text.hasPrefix("[") && text.hasSuffix("]")) || (text.hasPrefix("(") && text.hasSuffix(")"))
    }
}
