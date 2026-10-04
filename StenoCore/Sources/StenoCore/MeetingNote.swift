import Foundation

/// Il file nel Vault con frontmatter, Zona gestita e Note personali di una Riunione.
///
/// Steno riscrive solo la Zona gestita e le proprie chiavi del frontmatter:
/// tutto il resto appartiene all'utente.
public struct MeetingNote: Equatable, Sendable {
    /// Le chiavi del frontmatter che appartengono a Steno. `data` e `tags` si scrivono
    /// solo alla creazione e poi sono dell'utente, quindi qui non compaiono.
    public enum StenoKey: String, Sendable {
        case stenoID = "steno_id"
        case duration = "durata"
        case language = "lingua"
        case transcriptionProvider = "provider_trascrizione"
        case summaryProvider = "provider_riepilogo"
        case template
        case transcript = "trascrizione"
    }

    public static let managedStart = "%% steno:inizio %%"
    public static let managedEnd = "%% steno:fine %%"
    public static let personalNotesHeading = "## Note personali"

    public private(set) var content: String

    /// Il contenuto viene normalizzato: niente BOM, a capo `\n`.
    public init(content: String) {
        var normalized = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }
        self.content = normalized
    }

    public static func initial(stenoID: UUID, startedAt: Date, timeZone: TimeZone = .current) -> MeetingNote {
        MeetingNote(content: """
            ---
            steno_id: \(stenoID.uuidString)
            data: \(DateFormatter.posix("yyyy-MM-dd'T'HH:mm", timeZone: timeZone).string(from: startedAt))
            tags: [riunione]
            ---
            \(managedStart)
            ⏺ Registrazione in corso: il Riepilogo comparirà qui dopo lo stop.
            \(managedEnd)

            \(personalNotesHeading)


            """)
    }

    /// Lo `steno_id` del frontmatter, `nil` se manca (un testo uguale nel corpo non conta).
    public var stenoID: UUID? {
        let lines = content.components(separatedBy: "\n")
        guard let close = Self.frontmatterClose(in: lines) else { return nil }
        return lines[1..<close]
            .first { $0.hasPrefix("steno_id:") }
            .flatMap { UUID(uuidString: $0.dropFirst("steno_id:".count).trimmingCharacters(in: .whitespaces)) }
    }

    /// Sostituisce il testo tra i marcatori della Zona gestita con `body`.
    ///
    /// Se l'utente ha cancellato uno o entrambi i marcatori, quelli rimasti vengono tolti
    /// e la Zona gestita viene ricreata in cima al corpo, senza cancellare altro testo.
    /// I marcatori dentro i blocchi di codice non contano.
    public mutating func replaceManagedSection(with body: String) {
        var lines = content.components(separatedBy: "\n")
        // Un marcatore nel testo (es. nella risposta del modello) chiuderebbe la Zona gestita al giro dopo.
        let bodyLines = body.components(separatedBy: "\n")
            .filter { !Self.isLine($0, Self.managedStart) && !Self.isLine($0, Self.managedEnd) }

        if let managed = Self.managedRange(in: lines) {
            lines.replaceSubrange((managed.lowerBound + 1)..<managed.upperBound, with: bodyLines)
        } else {
            let strayMarkers = Self.markerLines(in: lines).map(\.index)
            for index in strayMarkers.reversed() {
                lines.remove(at: index)
            }
            let section = [Self.managedStart] + bodyLines + [Self.managedEnd, ""]
            lines.insert(contentsOf: section, at: Self.bodyStart(in: lines))
        }
        content = lines.joined(separator: "\n")
    }

    /// Tutto il corpo fuori dalla Zona gestita, senza l'intestazione delle Note personali
    /// e senza righe vuote doppie. Vuoto se l'utente non ha scritto niente.
    public var personalNotes: String {
        var lines = content.components(separatedBy: "\n")
        if let managed = Self.managedRange(in: lines) {
            lines.removeSubrange(managed)
        }
        lines.removeFirst(Self.bodyStart(in: lines))
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

    /// Com'è andato il Riepilogo di una Riunione.
    public enum SummaryOutcome: Equatable, Sendable {
        case written(text: String, template: String, provider: String)
        case failed(reason: String)
    }

    /// Registra l'esito dell'Elaborazione: chiavi di Steno nel frontmatter (ripristinando lo
    /// `steno_id` se l'utente l'ha cancellato), Riepilogo o motivo del fallimento e link alla
    /// Trascrizione nella Zona gestita.
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

        let summaryText: String
        switch summary {
        case .written(let text, let template, let provider):
            values += [(.template, template), (.summaryProvider, provider)]
            summaryText = text
        case .failed(let reason):
            summaryText = "⚠️ Riepilogo non generato: \(reason)"
        }
        setFrontmatter(values)
        replaceManagedSection(with: "\(summaryText)\n\nTrascrizione completa: [[\(transcriptName)]]")
    }

    /// Registra un'Elaborazione fallita: il motivo compare nella Zona gestita.
    public mutating func recordFailure(stenoID: UUID, reason: String) {
        setFrontmatter([(.stenoID, stenoID.uuidString)])
        replaceManagedSection(with: "⚠️ \(reason)")
    }

    /// Link Obsidian come valore YAML (tra virgolette, altrimenti `[[` sarebbe una lista).
    public static func wikiLink(_ name: String) -> String {
        "\"[[\(name)]]\""
    }

    /// `47m`, oppure `1h 05m` oltre l'ora. Mai meno di un minuto.
    private static func durationValue(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes < 60 ? "\(minutes)m" : String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }

    /// Imposta le chiavi indicate (valori già in YAML): sostituisce quelle esistenti, comprese
    /// le eventuali righe di continuazione, e aggiunge le mancanti in fondo. Le altre chiavi restano.
    public mutating func setFrontmatter(_ values: [(key: StenoKey, value: String)]) {
        var lines = content.components(separatedBy: "\n")
        if Self.frontmatterClose(in: lines) == nil {
            lines.insert(contentsOf: ["---", "---"], at: 0)
        }
        for (stenoKey, value) in values {
            let key = stenoKey.rawValue
            let close = Self.frontmatterClose(in: lines)!
            let entry = "\(key): \(value)"
            guard let line = lines[1..<close].firstIndex(where: { $0.hasPrefix("\(key):") }) else {
                lines.insert(entry, at: close)
                continue
            }
            var next = line + 1
            while next < close, lines[next].first.map({ $0 == " " || $0 == "\t" || $0 == "-" }) == true {
                next += 1
            }
            lines.replaceSubrange(line..<next, with: [entry])
        }
        content = lines.joined(separator: "\n")
    }

    // MARK: - Struttura del file

    /// Indice della riga che chiude il frontmatter, `nil` se il file non ne ha uno.
    private static func frontmatterClose(in lines: [String]) -> Int? {
        guard let first = lines.first, isLine(first, "---") else { return nil }
        return lines.indices.dropFirst().first { isLine(lines[$0], "---") }
    }

    /// Indice della prima riga dopo il frontmatter (0 se non c'è frontmatter).
    private static func bodyStart(in lines: [String]) -> Int {
        frontmatterClose(in: lines).map { $0 + 1 } ?? 0
    }

    /// Righe del corpo che sono marcatori della Zona gestita, esclusi quelli nei blocchi di codice.
    private static func markerLines(in lines: [String]) -> [(index: Int, isStart: Bool)] {
        var markers: [(index: Int, isStart: Bool)] = []
        var inCodeBlock = false
        for index in bodyStart(in: lines)..<lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inCodeBlock.toggle()
            } else if !inCodeBlock, line == managedStart || line == managedEnd {
                markers.append((index, line == managedStart))
            }
        }
        return markers
    }

    /// Righe dal marcatore d'inizio a quello di fine compresi, se ci sono entrambi e in ordine.
    private static func managedRange(in lines: [String]) -> ClosedRange<Int>? {
        let markers = markerLines(in: lines)
        guard let start = markers.firstIndex(where: \.isStart),
              let end = markers[(start + 1)...].first(where: { !$0.isStart })
        else { return nil }
        return markers[start].index...end.index
    }

    private static func isLine(_ line: String, _ marker: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == marker
    }
}

extension DateFormatter {
    /// Formattazione fissa, indipendente dalle impostazioni internazionali dell'utente.
    static func posix(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
