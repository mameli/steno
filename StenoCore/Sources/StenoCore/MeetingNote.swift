import Foundation

/// The file in the Vault with the frontmatter, the managed section and the personal notes of a Meeting.
///
/// Steno only rewrites the managed section and its own frontmatter keys: everything else
/// belongs to the user. Notes written before the English rewrite (Italian markers, keys and
/// heading) are recognised and moved to the English format whenever Steno writes them.
public struct MeetingNote: Equatable, Sendable {
    /// The frontmatter keys that belong to Steno. `date` and `tags` are written only at
    /// creation and belong to the user afterwards, so they are not listed here.
    public enum StenoKey: String, Sendable, CaseIterable {
        case stenoID = "steno_id"
        case duration
        case language
        case transcriptionProvider = "transcription_provider"
        case summaryProvider = "summary_provider"
        case template
        case transcript

        /// The key's name before the English rewrite.
        var legacyName: String? {
            switch self {
            case .duration: "durata"
            case .language: "lingua"
            case .transcriptionProvider: "provider_trascrizione"
            case .summaryProvider: "provider_riepilogo"
            case .transcript: "trascrizione"
            case .stenoID, .template: nil
            }
        }
    }

    /// How the Summary of a Meeting went.
    public enum SummaryOutcome: Equatable, Sendable {
        case written(text: String, template: String, provider: String)
        case failed(reason: String)
    }

    public static let managedStart = "%% steno:start %%"
    public static let managedEnd = "%% steno:end %%"
    public static let personalNotesHeading = "## Personal notes"
    private static let legacyManagedStart = "%% steno:inizio %%"
    private static let legacyManagedEnd = "%% steno:fine %%"
    private static let legacyPersonalNotesHeading = "## Note personali"

    public private(set) var content: String

    /// The content is normalised: no BOM, `\n` line endings.
    public init(content: String) {
        self.content = MarkdownLines(content).text
    }

    public static func initial(stenoID: UUID, startedAt: Date, timeZone: TimeZone = .current) -> MeetingNote {
        MeetingNote(content: """
            ---
            steno_id: \(stenoID.uuidString)
            date: \(DateFormatter.posix("yyyy-MM-dd'T'HH:mm", timeZone: timeZone).string(from: startedAt))
            tags: [meeting]
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

    /// Replaces the text between the managed section markers with `body`.
    ///
    /// If the user deleted one or both markers, the leftover ones are removed and the managed
    /// section is recreated at the top of the body, without deleting any other text. Markers
    /// inside code blocks do not count.
    public mutating func replaceManagedSection(with body: String) {
        var markdown = MarkdownLines(content)
        // A marker inside the text (e.g. in the model's reply) would close the managed section next time.
        let bodyLines = body.components(separatedBy: "\n").filter { Self.markerKind($0) == nil }
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

    /// The whole body outside the managed section, without the personal notes heading and
    /// without double blank lines. Empty if the user wrote nothing.
    public var personalNotes: String {
        var markdown = MarkdownLines(content)
        if let managed = Self.managedRange(in: markdown) {
            markdown.lines.removeSubrange(managed)
        }
        var lines = Array(markdown.lines.dropFirst(markdown.bodyStart))
        lines.removeAll { [Self.personalNotesHeading, Self.legacyPersonalNotesHeading].contains($0.trimmingCharacters(in: .whitespaces)) }

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
        stenoID: UUID, duration: TimeInterval, language: String?, transcriptionProvider: String,
        transcriptName: String, summary: SummaryOutcome
    ) {
        var values: [(key: StenoKey, value: String)] = [
            (.stenoID, stenoID.uuidString),
            (.duration, Self.durationValue(duration)),
            (.transcriptionProvider, transcriptionProvider),
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

    /// Records a failed Processing: the reason appears in the managed section.
    public mutating func recordFailure(stenoID: UUID, reason: String) {
        setFrontmatter([(.stenoID, stenoID.uuidString)])
        replaceManagedSection(with: "⚠️ \(reason)")
    }

    /// Obsidian link as a YAML value (quoted, otherwise `[[` would be a list).
    public static func wikiLink(_ name: String) -> String {
        "\"[[\(name)]]\""
    }

    /// Sets the given keys (values already in YAML): replaces existing ones, including any
    /// continuation lines and their pre-rewrite Italian name, and appends missing ones at the end.
    /// Other keys stay.
    public mutating func setFrontmatter(_ values: [(key: StenoKey, value: String)]) {
        var markdown = MarkdownLines(content)
        if markdown.frontmatterClose == nil {
            markdown.lines.insert(contentsOf: ["---", "---"], at: 0)
        }
        for (key, value) in values {
            let names = [key.rawValue] + (key.legacyName.map { [$0] } ?? [])
            let entry = "\(key.rawValue): \(value)"
            var replaced = false
            for name in names {
                let close = markdown.frontmatterClose!
                guard let line = markdown.lines[1..<close].firstIndex(where: { $0.hasPrefix("\(name):") }) else { continue }
                var next = line + 1
                while next < close, markdown.lines[next].first.map({ $0 == " " || $0 == "\t" || $0 == "-" }) == true {
                    next += 1
                }
                markdown.lines.replaceSubrange(line..<next, with: replaced ? [] : [entry])
                replaced = true
            }
            if !replaced {
                markdown.lines.insert(entry, at: markdown.frontmatterClose!)
            }
        }
        content = markdown.text
    }

    // MARK: - Private

    private mutating func recordSummary(stenoID: UUID, transcriptName: String, summary: SummaryOutcome) {
        var values: [(key: StenoKey, value: String)] = [(.stenoID, stenoID.uuidString)]
        let summaryText: String
        switch summary {
        case .written(let text, let template, let provider):
            values += [(.template, template), (.summaryProvider, provider)]
            summaryText = text
        case .failed(let reason):
            summaryText = "⚠️ Summary not generated: \(reason)"
        }
        setFrontmatter(values)
        replaceManagedSection(with: "\(summaryText)\n\nFull transcript: [[\(transcriptName)]]")
    }

    /// `47m`, or `1h 05m` past the hour. Never less than a minute.
    private static func durationValue(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes < 60 ? "\(minutes)m" : String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }

    /// Whether a line is a start or end marker of the managed section (also the Italian ones).
    private static func markerKind(_ line: String) -> Bool? {
        switch line.trimmingCharacters(in: .whitespaces) {
        case managedStart, legacyManagedStart: true
        case managedEnd, legacyManagedEnd: false
        default: nil
        }
    }

    /// Body lines that are managed section markers, except those inside code blocks.
    private static func markerLines(in markdown: MarkdownLines) -> [(index: Int, isStart: Bool)] {
        var markers: [(index: Int, isStart: Bool)] = []
        var inCodeBlock = false
        for index in markdown.bodyStart..<markdown.lines.count {
            let line = markdown.lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inCodeBlock.toggle()
            } else if !inCodeBlock, let isStart = markerKind(line) {
                markers.append((index, isStart))
            }
        }
        return markers
    }

    /// Lines from the start marker to the end marker included, if both are there and in order.
    private static func managedRange(in markdown: MarkdownLines) -> ClosedRange<Int>? {
        let markers = markerLines(in: markdown)
        guard let start = markers.firstIndex(where: \.isStart),
              let end = markers[(start + 1)...].first(where: { !$0.isStart })
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
