import Foundation

/// Lo stato dell'Elaborazione di una Riunione, salvato nella cartella della Registrazione
/// (`elaborazione.json`) così che sopravviva a un riavvio o a un crash dell'app.
public struct ProcessingRecord: Codable, Equatable, Sendable {
    public enum Status: Codable, Equatable, Sendable {
        /// La Riunione è in registrazione (se l'app si riavvia in questo stato, c'è stato un crash).
        case recording
        case queued
        case processing
        /// Nuovo Riepilogo dalla Trascrizione nel Vault; non riguarda l'audio.
        case regenerating
        case completed
        case failed(reason: String)

        /// Non ancora conclusa: non si cancella l'audio e non si offre Riprova né Rigenera.
        public var isPending: Bool {
            switch self {
            case .recording, .queued, .processing, .regenerating: true
            case .completed, .failed: false
            }
        }

        /// Riprova e Rigenera hanno senso solo per una Riunione già conclusa.
        public var canRetry: Bool { !isPending }
    }

    public struct InvalidTransition: Error, Equatable {
        public let from: Status
    }

    /// Che cosa fare dopo un riavvio dell'app.
    public struct RestartPlan: Sendable {
        /// Elaborazioni da (ri)fare, dalla Riunione più vecchia.
        public let toProcess: [ProcessingRecord]
        /// Stati da correggere su disco senza rielaborare.
        public let toSave: [ProcessingRecord]
    }

    public let stenoID: UUID
    public let startedAt: Date
    public var status: Status
    public var templateName: String
    /// Fissato all'avvio della Riunione (ADR 0001).
    public var summaryProfile: ProviderProfile?
    /// Percorso della Nota della Riunione, se è stata creata.
    public var noteURL: URL?

    public init(
        stenoID: UUID, startedAt: Date, status: Status,
        templateName: String, summaryProfile: ProviderProfile?, noteURL: URL?
    ) {
        self.stenoID = stenoID
        self.startedAt = startedAt
        self.status = status
        self.templateName = templateName
        self.summaryProfile = summaryProfile
        self.noteURL = noteURL
    }

    /// Dopo un riavvio: si riprendono le Riunioni in coda, in corso o interrotte durante la
    /// registrazione. Una Rigenerazione interrotta non va rifatta come Elaborazione completa
    /// (l'audio potrebbe non esserci più): la Riunione torna semplicemente completata.
    public static func afterRestart(_ records: [ProcessingRecord]) -> RestartPlan {
        let toProcess = records
            .filter { [.recording, .queued, .processing].contains($0.status) }
            .sorted { $0.startedAt < $1.startedAt }
        let toSave = records
            .filter { $0.status == .regenerating }
            .map { record in
                var record = record
                record.status = .completed
                return record
            }
        return RestartPlan(toProcess: toProcess, toSave: toSave)
    }

    /// Rimette in coda una Riunione conclusa per rifare tutta l'Elaborazione.
    public mutating func queueForRetry() throws {
        guard status.canRetry else { throw InvalidTransition(from: status) }
        status = .queued
    }

    public mutating func beginRegeneration() throws {
        guard status.canRetry else { throw InvalidTransition(from: status) }
        status = .regenerating
    }

    public static let fileName = "elaborazione.json"

    public static func load(from directory: URL) throws -> ProcessingRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProcessingRecord.self, from: Data(contentsOf: directory.appending(path: fileName)))
    }

    public func save(in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: directory.appending(path: Self.fileName), options: .atomic)
    }
}
