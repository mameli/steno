import EventKit
import StenoCore
import os

private let logger = Logger(subsystem: "dev.mameli.steno", category: "calendar")

/// The calendar event a Meeting is for, read from the Mac's calendars when the user turned it on
/// in Settings. EventKit reads the calendars on the Mac: nothing is sent anywhere.
enum MeetingCalendar {
    static var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Asks macOS for access to the calendars; the first time it shows the prompt.
    static func requestAccess() async -> Bool {
        do {
            return try await EKEventStore().requestFullAccessToEvents()
        } catch {
            logger.error("Calendar access request failed: \(error, privacy: .public)")
            return false
        }
    }

    /// The event in progress (see `CalendarEvent.inProgress`), `nil` if the calendar is off,
    /// not allowed, or there is none.
    static func eventInProgress(at now: Date) -> CalendarEvent? {
        guard AppSettings.useCalendar, isAuthorized else { return nil }
        let store = EKEventStore()
        let predicate = store.predicateForEvents(
            withStart: now, end: now.addingTimeInterval(CalendarEvent.earlyStart), calendars: nil
        )
        let events = store.events(matching: predicate).map { event in
            let declined = event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
            return CalendarEvent(
                title: event.title ?? "",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                isSkipped: event.status == .canceled || declined,
                participants: (event.attendees ?? []).compactMap(participantName)
            )
        }
        return CalendarEvent.inProgress(events, at: now)
    }

    /// The name of a person invited, or their email without one; `nil` for the user, rooms and resources.
    private static func participantName(_ participant: EKParticipant) -> String? {
        guard !participant.isCurrentUser, participant.participantType != .room,
              participant.participantType != .resource
        else { return nil }
        if let name = participant.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        let address = participant.url.absoluteString
        return address.hasPrefix("mailto:") ? String(address.dropFirst("mailto:".count)) : nil
    }
}
