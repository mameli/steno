import Foundation
import Testing
import StenoCore

@Suite("Title and rename")
struct MeetingTitleTests {
    let rome = TimeZone(identifier: "Europe/Rome")!
    /// 4 October 2026, 14:30 in Rome.
    let startedAt = Date(timeIntervalSince1970: 1_791_117_000)

    @Test("the generated title is cleaned up", arguments: [
        ("Q4 budget and hiring.", "Q4 budget and hiring"),
        ("Title: \"Project Alpha kickoff\"", "Project Alpha kickoff"),
        ("# Sprint 12 retro\n\nAnother line", "Sprint 12 retro"),
        ("«Release plan»", "Release plan"),
        ("**Client alignment**", "Client alignment"),
        ("**Title:** Next quarter budget", "Next quarter budget"),
        ("## Titolo: \"Retro\".", "Retro"),
        ("A meeting with far too many words for a title", "A meeting with far too many"),
    ])
    func clean(reply: String, expected: String) {
        #expect(MeetingTitle.clean(reply) == expected)
    }

    @Test("a reply without words is not a title", arguments: ["", "  \n ", "\"\"", "Title:"])
    func empty(reply: String) {
        #expect(MeetingTitle.clean(reply) == nil)
    }

    @Test("the title request contains the Summary and names the language")
    func request() {
        let messages = MeetingTitle.request(summary: "### Budget\n- Approved.", language: "it")

        #expect(messages.last?.content.contains("### Budget\n- Approved.") == true)
        #expect(messages.first?.content.contains("in Italian") == true)
        #expect(messages.first?.content.contains("6 words") == true)
    }

    @Test("the note is renamed only while it still has its provisional name")
    func rename() {
        func renamed(_ current: String) -> String? {
            VaultNaming.renamedNoteName(current: current, startedAt: startedAt, title: "Q4 budget", timeZone: rome)
        }

        #expect(renamed("2026-10-04 1430 - Meeting") == "2026-10-04 1430 - Q4 budget")
        #expect(renamed("2026-10-04 1430 - Meeting (2)") == "2026-10-04 1430 - Q4 budget")
        #expect(renamed("Budget with Mario") == nil)
        #expect(renamed("2026-10-04 1430 - Meeting with Mario") == nil)
        #expect(renamed("2026-10-03 1430 - Meeting") == nil)
        #expect(renamed("2026-10-04 1430 - Meeting (½)") == nil)
    }
}
