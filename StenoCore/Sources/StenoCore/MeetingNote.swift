import Foundation

/// The file in the Vault with the frontmatter, the Managed section and the personal notes of a Meeting.
///
/// Steno only rewrites the Managed section and its own frontmatter keys: everything else
/// belongs to the user.
public struct MeetingNote: Equatable, Sendable {
    /// The frontmatter keys that belong to Steno. `date` and `tags` are written only at
    /// creation and belong to the user afterwards, so they are not listed here.
    public enum StenoKey: String, Sendable, CaseIterable {
        case stenoID = "steno_id"
        case duration
        case language
        case summaryProvider = "summary_provider"
        case template
        case transcript
    }

    /// How the Summary of a Meeting went.
    public enum SummaryOutcome: Equatable, Sendable {
        case written(text: String, template: String, provider: String)
        /// No Summary Profile chosen: the note holds only the Transcript link.
        case transcriptOnly
        case failed(reason: String)
    }

    public static let managedStart = "%% steno:start %%"
    public static let managedEnd = "%% steno:end %%"
    public static let personalNotesHeading = "## Personal notes"

    private enum Marker {
        case start, end

        init?(_ line: String) {
            switch line.trimmingCharacters(in: .whitespaces) {
            case MeetingNote.managedStart: self = .start
            case MeetingNote.managedEnd: self = .end
            default: return nil
            }
        }
    }

    public private(set) var content: String

    /// The content is normalised: no BOM, `\n` line endings.
    public init(content: String) {
        self.content = MarkdownLines(content).text
    }

    /// `participants`: the invited participants of the calendar event, if there is one. Like `date`
    /// and `tags` they are written only here and belong to the user afterwards.
    public static func initial(
        stenoID: UUID, startedAt: Date, participants: [String] = [], timeZone: TimeZone = .current
    ) -> MeetingNote {
        let participantsEntry = participants.isEmpty ? "" : "\nparticipants:" + participants.map {
            "\n  - \"\($0.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "\\\""))\""
        }.joined()
        return MeetingNote(content: """
            ---
            steno_id: \(stenoID.uuidString)
            date: \(DateFormatter.posix("yyyy-MM-dd'T'HH:mm", timeZone: timeZone).string(from: startedAt))
            tags: [meeting]\(participantsEntry)
            ---
            \(managedStart)
            ⏺ Recording in progress: the summary will appear here after you stop.
            \(managedEnd)

            \(personalNotesHeading)


            """)
    }

    /// The frontmatter `steno_id`, `nil` if missing (the same text in the body does not count).
    public var stenoID: UUID? {
        MarkdownLines(content).value(StenoKey.stenoID.rawValue).flatMap(UUID.init(uuidString:))
    }

    /// The names the user gave the Speakers, from the frontmatter list `speakers`
    /// (`- Speaker 1 = Mario Rossi`). Entries in another form are ignored; for a number given
    /// twice, the first one counts.
    public var speakerNames: [Int: String] {
        var names: [Int: String] = [:]
        for entry in MarkdownLines(content).list("speakers") ?? [] {
            guard let match = entry.wholeMatch(of: /[Ss]peaker\s+(\d+)\s*=\s*(.*\S)\s*/),
                  let number = Int(match.1), names[number] == nil
            else { continue }
            names[number] = String(match.2)
        }
        return names
    }

    /// The invited participants written at the start from the calendar, as the user left them.
    public var participants: [String] {
        MarkdownLines(content).list("participants") ?? []
    }

    /// Replaces the text between the Managed section markers with `body`.
    ///
    /// If the user deleted one or both markers, the leftover ones are removed and the managed
    /// section is recreated at the top of the body, without deleting any other text. Markers
    /// inside code blocks do not count.
    public mutating func replaceManagedSection(with body: String) {
        var markdown = MarkdownLines(content)
        // A marker inside the text (e.g. in the model's reply) would close the Managed section next time.
        let bodyLines = body.components(separatedBy: "\n").filter { Marker($0) == nil }
        let section = [Self.managedStart] + bodyLines + [Self.managedEnd]

        if let managed = Self.managedRange(in: markdown) {
            markdown.lines.replaceSubrange(managed, with: section)
        } else {
            for index in Self.markerLines(in: markdown).map(\.index).reversed() {
                markdown.lines.remove(at: index)
            }
            markdown.lines.insert(contentsOf: section + [""], at: markdown.bodyStart)
        }
        content = markdown.text
    }

    /// The whole body outside the Managed section, without the Personal notes heading and
    /// without double blank lines. Empty if the user wrote nothing.
    public var personalNotes: String {
        var markdown = MarkdownLines(content)
        if let managed = Self.managedRange(in: markdown) {
            markdown.lines.removeSubrange(managed)
        }
        var lines = Array(markdown.lines.dropFirst(markdown.bodyStart))
        lines.removeAll { $0.trimmingCharacters(in: .whitespaces) == Self.personalNotesHeading }

        var kept: [String] = []
        for line in lines {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            let previousIsBlank = kept.last?.isEmpty ?? true
            if isBlank && previousIsBlank { continue }
            kept.append(isBlank ? "" : line)
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Records the outcome of Processing: Steno's frontmatter keys (restoring `steno_id` if the
    /// user deleted it), the Summary or the failure reason, and the Transcript link in the
    /// managed section.
    public mutating func recordProcessing(
        stenoID: UUID, duration: TimeInterval, language: String?, transcriptName: String,
        summary: SummaryOutcome
    ) {
        var values: [(key: StenoKey, value: String)] = [
            (.stenoID, stenoID.uuidString),
            (.duration, Self.durationValue(duration)),
            (.transcript, Self.wikiLink(transcriptName)),
        ]
        if let language { values.append((.language, language)) }
        setFrontmatter(values)
        recordSummary(stenoID: stenoID, transcriptName: transcriptName, summary: summary)
    }

    /// Records a new Summary of a Meeting already processed: Summary, Template and provider
    /// change, while duration, language and Transcript stay those of the Processing.
    public mutating func recordRegeneration(stenoID: UUID, transcriptName: String, summary: SummaryOutcome) {
        recordSummary(stenoID: stenoID, transcriptName: transcriptName, summary: summary)
    }

    /// Records a failed Processing: the reason appears in the Managed section.
    public mutating func recordFailure(stenoID: UUID, reason: String) {
        setFrontmatter([(.stenoID, stenoID.uuidString)])
        replaceManagedSection(with: "⚠️ \(reason)")
    }

    /// Obsidian link as a YAML value (quoted, otherwise `[[` would be a list).
    public static func wikiLink(_ name: String) -> String {
        "\"[[\(name)]]\""
    }

    /// Sets the given keys (values already in YAML): replaces existing ones, including any
    /// continuation lines, and appends missing ones at the end. Other keys stay.
    public mutating func setFrontmatter(_ values: [(key: StenoKey, value: String)]) {
        var markdown = MarkdownLines(content)
        if markdown.frontmatterClose == nil {
            markdown.lines.insert(contentsOf: ["---", "---"], at: 0)
        }
        for (key, value) in values {
            let entry = "\(key.rawValue): \(value)"
            guard let entryLines = Self.entryLines(key, in: markdown) else {
                markdown.lines.insert(entry, at: markdown.frontmatterClose!)
                continue
            }
            markdown.lines.replaceSubrange(entryLines, with: [entry])
        }
        content = markdown.text
    }

    // MARK: - Private

    private mutating func removeFrontmatter(_ keys: [StenoKey]) {
        var markdown = MarkdownLines(content)
        for key in keys {
            if let entryLines = Self.entryLines(key, in: markdown) { markdown.lines.removeSubrange(entryLines) }
        }
        content = markdown.text
    }

    /// The lines of a frontmatter entry, including the indented lines of a multi-line value.
    private static func entryLines(_ key: StenoKey, in markdown: MarkdownLines) -> Range<Int>? {
        guard let close = markdown.frontmatterClose,
              let line = markdown.lines[1..<close].firstIndex(where: { $0.hasPrefix("\(key.rawValue):") })
        else { return nil }
        var next = line + 1
        while next < close, markdown.lines[next].first.map({ $0 == " " || $0 == "\t" || $0 == "-" }) == true {
            next += 1
        }
        return line..<next
    }

    private mutating func recordSummary(stenoID: UUID, transcriptName: String, summary: SummaryOutcome) {
        var values: [(key: StenoKey, value: String)] = [(.stenoID, stenoID.uuidString)]
        let transcriptLink = "Full transcript: [[\(transcriptName)]]"
        let body: String
        switch summary {
        case .written(let text, let template, let provider):
            values += [(.template, template), (.summaryProvider, provider)]
            body = "\(text)\n\n\(transcriptLink)"
        case .transcriptOnly:
            removeFrontmatter([.template, .summaryProvider])
            body = transcriptLink
        case .failed(let reason):
            body = "⚠️ Summary not generated: \(reason)\n\n\(transcriptLink)"
        }
        setFrontmatter(values)
        replaceManagedSection(with: body)
    }

    /// `47m`, or `1h 05m` past the hour. Never less than a minute.
    private static func durationValue(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes < 60 ? "\(minutes)m" : String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }

    /// Body lines that are Managed section markers, except those inside code blocks.
    private static func markerLines(in markdown: MarkdownLines) -> [(index: Int, marker: Marker)] {
        var markers: [(index: Int, marker: Marker)] = []
        var inCodeBlock = false
        for index in markdown.bodyStart..<markdown.lines.count {
            let line = markdown.lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inCodeBlock.toggle()
            } else if !inCodeBlock, let marker = Marker(line) {
                markers.append((index, marker))
            }
        }
        return markers
    }

    /// Lines from the start marker to the end marker included, if both are there and in order.
    private static func managedRange(in markdown: MarkdownLines) -> ClosedRange<Int>? {
        let markers = markerLines(in: markdown)
        guard let start = markers.firstIndex(where: { $0.marker == .start }),
              let end = markers[(start + 1)...].first(where: { $0.marker == .end })
        else { return nil }
        return markers[start].index...end.index
    }
}

extension DateFormatter {
    /// Fixed formatting, independent of the user's regional settings.
    static func posix(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
