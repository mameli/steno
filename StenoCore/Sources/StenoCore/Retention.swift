import Foundation

/// How long the audio of a Meeting is kept. The Transcript stays in the Vault forever.
public enum Retention {
    public static let days = 7

    public struct Item: Sendable {
        public let stenoID: UUID
        public let startedAt: Date
        /// `nil` for Recordings without a saved state (made before the persistent queue).
        public let status: ProcessingRecord.Status?

        public init(stenoID: UUID, startedAt: Date, status: ProcessingRecord.Status?) {
            self.stenoID = stenoID
            self.startedAt = startedAt
            self.status = status
        }
    }

    /// Recordings to delete: older than `days` days and already concluded (processed or
    /// failed). Those still pending are kept.
    public static func expired(_ items: [Item], now: Date, days: Int = days) -> [UUID] {
        let limit = now.addingTimeInterval(-Double(days) * 86_400)
        return items
            .filter { $0.startedAt < limit && $0.status?.isPending != true }
            .map(\.stenoID)
    }
}
