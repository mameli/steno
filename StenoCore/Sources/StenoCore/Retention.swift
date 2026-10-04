import Foundation

/// Per quanto si tiene l'audio di una Riunione. La Trascrizione resta nel Vault per sempre.
public enum Retention {
    public static let days = 7

    public struct Item: Sendable {
        public let stenoID: UUID
        public let startedAt: Date
        /// `nil` per le Registrazioni senza stato salvato (create prima della coda persistente).
        public let status: ProcessingRecord.Status?

        public init(stenoID: UUID, startedAt: Date, status: ProcessingRecord.Status?) {
            self.stenoID = stenoID
            self.startedAt = startedAt
            self.status = status
        }
    }

    /// Le Registrazioni da cancellare: più vecchie di `days` giorni e già concluse (elaborate o
    /// fallite). Quelle ancora da concludere restano.
    public static func expired(_ items: [Item], now: Date, days: Int = days) -> [UUID] {
        let limit = now.addingTimeInterval(-Double(days) * 86_400)
        return items
            .filter { $0.startedAt < limit && $0.status?.isPending != true }
            .map(\.stenoID)
    }
}
