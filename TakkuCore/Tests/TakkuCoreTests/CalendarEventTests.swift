import Foundation
import Testing
import TakkuCore

@Suite("Calendar event of a Meeting")
struct CalendarEventTests {
    let now = Date(timeIntervalSince1970: 1_791_117_000)

    func event(
        _ title: String, start minutes: Double, length: Double = 30, allDay: Bool = false, skipped: Bool = false,
        participants: [String] = ["Mario Rossi"]
    ) -> CalendarEvent {
        CalendarEvent(
            title: title, start: now.addingTimeInterval(minutes * 60), end: now.addingTimeInterval((minutes + length) * 60),
            isAllDay: allDay, isSkipped: skipped, participants: participants
        )
    }

    @Test("the event in progress or starting within 10 minutes, not one ended, later or all-day")
    func inProgress() {
        #expect(CalendarEvent.inProgress([event("Sync", start: -5)], at: now)?.title == "Sync")
        #expect(CalendarEvent.inProgress([event("Early", start: 8)], at: now)?.title == "Early")
        #expect(CalendarEvent.inProgress([event("Later", start: 15)], at: now) == nil)
        #expect(CalendarEvent.inProgress([event("Over", start: -40)], at: now) == nil)
        #expect(CalendarEvent.inProgress([event("Holiday", start: -600, length: 1440, allDay: true)], at: now) == nil)
    }

    @Test("cancelled or declined events are skipped")
    func skipped() {
        #expect(CalendarEvent.inProgress([event("Declined", start: 0, skipped: true)], at: now) == nil)
    }

    @Test("among several, one with participants first, then the start closest to now")
    func choice() {
        let focus = event("Focus time", start: -1, length: 120, participants: [])
        let call = event("Call", start: -20)
        let next = event("Next call", start: 3)

        #expect(CalendarEvent.inProgress([focus, call], at: now)?.title == "Call")
        #expect(CalendarEvent.inProgress([call, next, focus], at: now)?.title == "Next call")
        #expect(CalendarEvent.inProgress([focus], at: now)?.title == "Focus time")
    }
}
