import Foundation

/// What Steno asks the model in order to write the Summary of a Meeting.
///
/// The instructions are in English; the Summary language is stated explicitly
/// ("Write the summary in Italian"), so any language works.
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

    /// Language code: the Template's, else the Meeting's, else Italian.
    public var summaryLanguage: String {
        template.summaryLanguage ?? meetingLanguage ?? "it"
    }

    /// A single request with the whole Transcript.
    public func singleRequest() -> [ChatMessage] {
        [
            ChatMessage(role: .system, content: systemRules),
            ChatMessage(role: .user, content: """
                \(templateAndNotes)

                # Transcript
                \(transcript.markdown.trimmingCharacters(in: .newlines))
                """),
        ]
    }

    /// Room left for the model's reply in every request.
    public static let replyReserveTokens = 4_096

    /// Conservative estimate: about 3 characters per token (Italian uses more tokens than English).
    static func estimatedTokens(_ messages: [ChatMessage]) -> Int {
        messages.reduce(0) { $0 + $1.content.count / 3 + 4 }
    }

    func fits(maxContextTokens: Int) -> Bool {
        Self.estimatedTokens(singleRequest()) + Self.replyReserveTokens <= maxContextTokens
    }

    /// The Transcript split into blocks of consecutive paragraphs, one request per block.
    /// A paragraph is never split: if it alone exceeds the room, it forms its own block.
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

    /// When the merge does not fit in the context: consecutive partial summaries are grouped
    /// and every group becomes a single summary, one request per group.
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

    /// Merges the partial summaries into a Summary that follows the Template.
    func mergeRequest(partials: [String]) -> [ChatMessage] {
        let parts = partials.enumerated()
            .map { "Part \($0.offset + 1) of \(partials.count):\n\($0.element)" }
            .joined(separator: "\n\n")
        return [
            ChatMessage(role: .system, content: systemRules),
            ChatMessage(role: .user, content: """
                \(templateAndNotes)

                # Transcript
                The Transcript was too long for a single request: below are summaries of its parts, in order.

                \(parts)
                """),
        ]
    }

    private var systemRules: String {
        """
        You are Steno and you write the summary of a meeting from its Transcript.

        Rules:
        - Write the summary in \(languageName), whatever language the instructions are written in.
        - Follow the structure and instructions of the Template.
        - Do not invent: use only what is in the Transcript and in the personal notes.
        - In the Transcript "Me" is the person who took the personal notes, "Others" are the other participants, not told apart.
        - The personal notes say what matters to the person who wrote them: give those topics priority.
        - Write actions as a `- [ ]` checklist, in the format the Template asks for; if it asks for none, `- [ ] who: what (when)`. Leave out who or when if they are not clear.
        - Reply with the summary in Markdown only, without preambles.
        """
    }

    private func partialRequest(part: Int, of count: Int, transcript: String) -> [ChatMessage] {
        [
            ChatMessage(role: .system, content: """
                You are Steno. You receive part \(part) of \(count) of the Transcript of a meeting.
                Summarise it faithfully and compactly, in \(languageName): topics, decisions, actions (who, what, when) and open questions, with timestamps.
                In the Transcript "Me" is the person who took the personal notes, "Others" are the other participants.
                Do not invent. Reply with the summary only.
                """),
            ChatMessage(role: .user, content: """
                # Personal notes
                \(notesOrNone)

                # Transcript, part \(part) of \(count)
                \(transcript)
                """),
        ]
    }

    private func groupRequest(_ partials: String) -> [ChatMessage] {
        [
            ChatMessage(role: .system, content: """
                You are Steno. You receive the summaries of consecutive parts of the same meeting.
                Merge them into a single faithful and compact summary, in \(languageName): topics, decisions, actions (who, what, when) and open questions, with timestamps.
                Do not invent. Reply with the summary only.
                """),
            ChatMessage(role: .user, content: """
                # Personal notes
                \(notesOrNone)

                # Summaries of consecutive parts
                \(partials)
                """),
        ]
    }

    private var templateAndNotes: String {
        """
        # Template
        \(template.body)

        # Personal notes
        \(notesOrNone)
        """
    }

    private var notesOrNone: String {
        personalNotes.isEmpty ? "(none)" : personalNotes
    }

    private var languageName: String {
        Language.name(summaryLanguage)
    }
}
