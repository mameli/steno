import Foundation

/// What Takku asks the model in order to write the Summary of a Meeting.
///
/// The instructions are in English; the Summary language is stated explicitly
/// ("Write the summary in Italian"), so any language works.
public struct SummaryPrompt: Sendable {
    private let template: Template
    private let personalNotes: String
    private let transcript: Transcript
    private let meetingLanguage: String?
    private let vocabulary: Vocabulary
    private let userName: String?
    private let participants: [String]

    /// `userName` is who "Me" is in the Transcript, so the Summary names them as the others call them.
    /// `participants`: who the calendar event invited, as the Meeting note lists them now.
    public init(
        template: Template, personalNotes: String, transcript: Transcript, meetingLanguage: String?,
        vocabulary: Vocabulary = .empty, userName: String? = nil, participants: [String] = []
    ) {
        self.template = template
        self.personalNotes = personalNotes
        self.transcript = transcript
        self.meetingLanguage = meetingLanguage
        self.vocabulary = vocabulary
        self.userName = userName.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        self.participants = participants
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
        You are Takku and you write the summary of a meeting from its Transcript.

        Rules:
        - Write the summary in \(languageName), whatever language the instructions are written in.
        - Follow the structure and instructions of the Template.
        - Do not invent: use only what is in the Transcript and in the personal notes.
        - For every bullet, actions included, end it with the time of the Transcript passage it comes from, in square brackets as in the Transcript: `[12:34]`, or `[03:10] [07:45]` for several. Leave out what you cannot point to in the Transcript or in the personal notes. Takku removes the times before showing the summary: do not mention them otherwise.
        - \(Self.truncationRule)
        - \(meRule)
        - \(Self.speakersRule)\(namedSpeakersRule.map { "\n- " + $0 } ?? "")\(participantsRule.map { "\n- " + $0 } ?? "")
        - The personal notes say what matters to the person who wrote them: give those topics priority.\(marksRule.map { "\n- " + $0 } ?? "")
        - Write actions as a `- [ ]` checklist, in the format the Template asks for; if it asks for none, `- [ ] who: what (when)`. Leave out who or when if they are not clear, with nothing in their place.
        - Reply with the summary in Markdown only, without preambles.
        """ + vocabularyBlock
    }

    /// "Me" is a Track label, not a name: written as is it reads "Me ha esplorato…", and without the
    /// user's name the model takes "Mario", as the others call them, for someone else.
    private var meRule: String {
        if let userName {
            """
            In the Transcript "Me" is \(userName), the person who took the personal notes; the others may call them by their first name. In the summary write about them by name like any other participant, never as "Me".
            """
        } else {
            """
            In the Transcript "Me" is the person who took the personal notes. Never write "Me" in the summary: if a name they answer to is clear, use it, otherwise leave out who.
            """
        }
    }

    /// Speakers are told apart by voice only: their names come from what is said, when it is clear.
    /// An unnamed Speaker keeps the label only on an action, where "who" is worth a guess for the reader.
    private static let speakersRule = """
        The other participants are "Speaker 1", "Speaker 2"…, told apart by their voice: the same number is the same person throughout the Transcript, but a short reply can be given to the wrong one; "Others" is someone not told apart. A Speaker's name is the one they introduce themselves with, or the one they answer to when called: use it for what that Speaker says and takes on. For a Speaker without a name, say who they are if it is clear (e.g. "the supplier's team"). Otherwise write "Speaker N" only as who takes on an action, and leave out who everywhere else: never "Speaker N" in a heading or in the other bullets.
        """

    /// In the summaries of the parts of a long Meeting a Speaker's name may only come up in
    /// another part: the label is kept so the final summary can still name them.
    private static let partialSpeakersRule = """
        The other participants are "Speaker 1", "Speaker 2"…, told apart by their voice: the same number is the same person in every part; "Others" is someone not told apart. A Speaker's name is the one they introduce themselves with, or the one they answer to when called: write "Speaker N (Name)" when it is clear, otherwise keep "Speaker N".
        """

    /// "Name (Speaker N)" in the Transcript: the user named that Speaker in the Meeting note.
    private var namedSpeakersRule: String? {
        guard transcript.hasNamedSpeakers else { return nil }
        return """
            "Name (Speaker N)" in the Transcript is a name the user gave that Speaker: it is certain, always write that name for what they say and take on.
            """
    }

    /// Who was invited is not who spoke: a guess by elimination would put words in the wrong mouth.
    private var participantsRule: String? {
        guard !participants.isEmpty else { return nil }
        return """
            The invited participants are who the calendar invitation asked to join, not who spoke, and some may not have joined: a Speaker's name can be one of them only when the Transcript makes it clear, or when there is exactly one invited participant and one Speaker. Use them to spell names right.
            """
    }

    /// The user marked these paragraphs while recording (⌃⌥⌘M).
    private var marksRule: String? {
        guard transcript.paragraphs.contains(where: \.isMarked) else { return nil }
        return """
            Paragraphs starting with \(Transcript.markSymbol) were marked as important by the user during the meeting: give them priority, like the topics of the personal notes.
            """
    }

    /// A Recording stopped before the end of the Meeting leaves a Transcript cut mid-sentence: models
    /// tend to complete what was announced (the rest of a talk, its results) from what they know.
    private static let truncationRule = """
        The Transcript may stop mid-sentence, when the recording ended before the meeting: summarise only what it contains, and do not complete talks, lists, steps or results that are announced but not reached.
        """

    /// The Summary without the times the model cites (`[12:34]`, `[03:10] [07:45]`, `([1:02:45])`,
    /// `[04:00-06:30]`): they tie every point to the Transcript but are not meant to be read.
    /// Checkboxes, wikilinks and Markdown links have no times in their brackets and stay.
    public static func removingCitedTimes(_ summary: String) -> String {
        let time = #"\d{1,2}(?::\d{2}){1,2}"#
        let bracket = #"\[\#(time)(?:\s*[-–—,;]\s*\#(time))*\]"#
        let run = #"\#(bracket)(?:[ \t]*[,;]?[ \t]*\#(bracket))*"#
        let citedTimes = try! Regex(#"[ \t]*(?:\(\#(run)\)|\#(run))"#)
        return summary.replacing(citedTimes, with: "")
    }

    /// The Summary without the stars of the marked paragraphs, which the model sometimes copies:
    /// they tell it what matters, they are not meant to be read.
    public static func removingMarks(_ summary: String) -> String {
        // The emoji variant (⭐️) is another grapheme: made plain first, so one pattern covers both.
        summary
            .replacingOccurrences(of: Transcript.markSymbol + "\u{FE0F}", with: Transcript.markSymbol)
            // At the end of a line the spaces before it go too; elsewhere those after it.
            .replacing(try! Regex("[ \t]*\(Transcript.markSymbol)[ \t]*(?=\n|$)"), with: "")
            .replacing(try! Regex("\(Transcript.markSymbol)[ \t]*"), with: "")
    }

    /// The Vocabulary for the system prompt of any request, with a blank line before it; empty without one.
    private var vocabularyBlock: String {
        vocabulary.promptBlock.map { "\n\n" + $0 } ?? ""
    }

    private func partialRequest(part: Int, of count: Int, transcript: String) -> [ChatMessage] {
        [
            ChatMessage(role: .system, content: """
                You are Takku. You receive part \(part) of \(count) of the Transcript of a meeting.
                Summarise it faithfully and compactly, in \(languageName): topics, decisions, actions (who, what, when) and open questions, with timestamps.
                \(meRule)
                \(Self.partialSpeakersRule)\(namedSpeakersRule.map { "\n" + $0 } ?? "")\(marksRule.map { "\n" + $0 } ?? "")
                Do not invent. \(Self.truncationRule)
                Reply with the summary only.
                """ + vocabularyBlock),
            ChatMessage(role: .user, content: """
                # Personal notes
                \(notesOrNone)
                \(participantsBlock)
                # Transcript, part \(part) of \(count)
                \(transcript)
                """),
        ]
    }

    private func groupRequest(_ partials: String) -> [ChatMessage] {
        [
            ChatMessage(role: .system, content: """
                You are Takku. You receive the summaries of consecutive parts of the same meeting.
                Merge them into a single faithful and compact summary, in \(languageName): topics, decisions, actions (who, what, when) and open questions, with timestamps.
                "Speaker N" is the same person in every summary: keep it, with the name if one of them gives it.
                Do not invent. Reply with the summary only.
                """ + vocabularyBlock),
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
        \(notesOrNone)\(participantsBlock.isEmpty ? "" : "\n\n" + participantsBlock.trimmingCharacters(in: .newlines))
        """
    }

    /// The invited participants as a section of the user message, with a blank line after it; empty without any.
    private var participantsBlock: String {
        guard !participants.isEmpty else { return "" }
        return "\n# Invited participants\n" + participants.map { "- \($0)" }.joined(separator: "\n") + "\n"
    }

    private var notesOrNone: String {
        personalNotes.isEmpty ? "(none)" : personalNotes
    }

    private var languageName: String {
        Language.name(summaryLanguage)
    }
}
