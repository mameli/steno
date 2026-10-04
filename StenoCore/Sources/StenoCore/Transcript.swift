import Foundation

/// A stretch of speech recognised in a Track. Times in seconds from the start of the Meeting.
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

/// Consecutive Utterances of the same Track, shown with a single timestamp.
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

/// The spoken text of a Meeting, with the two Tracks merged in time order.
public struct Transcript: Sendable {
    /// The copy of the Transcript in the Recording folder (deleted together with the audio).
    public static let recordingCopyFileName = "transcript.md"

    /// After a longer pause the same Track starts a new paragraph with a new timestamp.
    public static let paragraphBreak: TimeInterval = 30
    /// An Utterance starting later than this from the paragraph start opens a new one,
    /// so even a long monologue gets a timestamp about every minute.
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

    private init(paragraphs: [Paragraph]) {
        self.paragraphs = paragraphs
    }

    /// Body of the Transcript file: `**[mm:ss] Me:** text`, one paragraph per block.
    public var markdown: String {
        Self.markdown(of: paragraphs)
    }

    static func markdown(of paragraphs: [Paragraph]) -> String {
        paragraphs
            .map { "**[\(elapsedLabel($0.start))] \($0.track.label):** \($0.text)\n" }
            .joined(separator: "\n")
    }

    /// Reads back the Transcript file written in the Vault (even if edited by hand): lines
    /// that do not start with `**[time] Me/Others:**` stay in the paragraph they are in.
    /// Files written before the English rewrite (`Io`/`Altri`, `lingua:`) are read too.
    public static func parse(vaultFile: String) -> (transcript: Transcript, language: String?) {
        let markdown = MarkdownLines(vaultFile)
        let language = markdown.value("language", "lingua")

        let header = /^\*\*\[(\d+(?::\d{2}){1,2})\] (Me|Others|Io|Altri):\*\* ?(.*)$/
        var paragraphs: [Paragraph] = []
        for line in markdown.lines[markdown.bodyStart...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = trimmed.wholeMatch(of: header) {
                let seconds = match.1.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
                let track: Track = (match.2 == "Me" || match.2 == "Io") ? .me : .others
                paragraphs.append(Paragraph(track: track, start: seconds, text: String(match.3)))
            } else if !trimmed.isEmpty, let last = paragraphs.popLast() {
                paragraphs.append(Paragraph(track: last.track, start: last.start, text: last.text + " " + trimmed))
            }
        }
        return (Transcript(paragraphs: paragraphs), language)
    }

    /// The Transcript file in the Vault: frontmatter linking back to the Meeting note.
    /// `language` is `nil` if no speech was heard in the Meeting.
    public func vaultFile(stenoID: UUID, meetingNoteName: String, language: String?) -> String {
        var frontmatter = ["---", "steno_id: \(stenoID.uuidString)", "meeting: \(MeetingNote.wikiLink(meetingNoteName))"]
        if let language { frontmatter.append("language: \(language)") }
        frontmatter.append("---")
        return frontmatter.joined(separator: "\n") + "\n" + markdown
    }

    /// Whisper describes non-speech in brackets (`[BLANK_AUDIO]`, `[Music]`)
    /// and on silence it makes up whole sentences in parentheses.
    private static func isAnnotation(_ text: String) -> Bool {
        (text.hasPrefix("[") && text.hasSuffix("]")) || (text.hasPrefix("(") && text.hasSuffix(")"))
    }
}
