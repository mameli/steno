import Foundation

/// A calendar event as Takku needs it, read from EventKit by the app.
public struct CalendarEvent: Equatable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    /// Cancelled, or declined by the user.
    public let isSkipped: Bool
    /// The invited participants, without the user, rooms and resources.
    public let participants: [String]

    public init(title: String, start: Date, end: Date, isAllDay: Bool, isSkipped: Bool, participants: [String]) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isSkipped = isSkipped
        self.participants = participants
    }

    /// A Meeting started this early is still for the event: people join a few minutes before.
    public static let earlyStart: TimeInterval = 10 * 60

    /// The event a Meeting starting `now` is for: not all-day, not cancelled or declined, starting
    /// at most 10 minutes from now and not ended yet. Among several, one with participants, then
    /// the one whose start is closest to now.
    public static func inProgress(_ events: [CalendarEvent], at now: Date) -> CalendarEvent? {
        events
            .filter { !$0.isAllDay && !$0.isSkipped && $0.start <= now.addingTimeInterval(earlyStart) && $0.end > now }
            .min { a, b in
                if a.participants.isEmpty != b.participants.isEmpty { return !a.participants.isEmpty }
                return abs(a.start.timeIntervalSince(now)) < abs(b.start.timeIntervalSince(now))
            }
    }
}
