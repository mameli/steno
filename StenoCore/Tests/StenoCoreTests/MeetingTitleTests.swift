import Foundation
import Testing
import StenoCore

@Suite("Titolo e rinomina")
struct MeetingTitleTests {
    let rome = TimeZone(identifier: "Europe/Rome")!
    /// 4 ottobre 2026, 14:30 a Roma.
    let startedAt = Date(timeIntervalSince1970: 1_791_117_000)

    @Test("il titolo generato viene ripulito", arguments: [
        ("Budget Q4 e assunzioni.", "Budget Q4 e assunzioni"),
        ("Titolo: \"Kickoff progetto Alfa\"", "Kickoff progetto Alfa"),
        ("# Retro sprint 12\n\nUn'altra riga", "Retro sprint 12"),
        ("«Piano di rilascio»", "Piano di rilascio"),
        ("**Allineamento con il cliente**", "Allineamento con il cliente"),
        ("**Titolo:** Budget del prossimo trimestre", "Budget del prossimo trimestre"),
        ("## Titolo: \"Retro\".", "Retro"),
        ("Una riunione con troppe parole per stare in un titolo", "Una riunione con troppe parole per"),
    ])
    func clean(reply: String, expected: String) {
        #expect(MeetingTitle.clean(reply) == expected)
    }

    @Test("una risposta senza parole non è un titolo", arguments: ["", "  \n ", "\"\"", "Titolo:"])
    func empty(reply: String) {
        #expect(MeetingTitle.clean(reply) == nil)
    }

    @Test("la richiesta del titolo contiene il Riepilogo e la lingua")
    func request() {
        let messages = MeetingTitle.request(summary: "## Sintesi\nBudget approvato.", language: "en")

        #expect(messages.last?.content.contains("## Sintesi\nBudget approvato.") == true)
        #expect(messages.first?.content.contains("in inglese") == true)
        #expect(messages.first?.content.contains("6 parole") == true)
    }

    @Test("la nota si rinomina solo se ha ancora il nome provvisorio")
    func rename() {
        func renamed(_ current: String) -> String? {
            VaultNaming.renamedNoteName(current: current, startedAt: startedAt, title: "Budget Q4", timeZone: rome)
        }

        #expect(renamed("2026-10-04 1430 - Riunione") == "2026-10-04 1430 - Budget Q4")
        #expect(renamed("2026-10-04 1430 - Riunione (2)") == "2026-10-04 1430 - Budget Q4")
        #expect(renamed("Budget con Mario") == nil)
        #expect(renamed("2026-10-04 1430 - Riunione con Mario") == nil)
        #expect(renamed("2026-10-03 1430 - Riunione") == nil)
        #expect(renamed("2026-10-04 1430 - Riunione (½)") == nil)
    }
}
