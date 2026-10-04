import Foundation
import Testing
import StenoCore

@Suite("Nomi dei file nel Vault")
struct VaultNamingTests {
    let rome = TimeZone(identifier: "Europe/Rome")!
    /// 4 ottobre 2026, 14:30 a Roma.
    let startedAt = Date(timeIntervalSince1970: 1_791_117_000)

    @Test("la Nota della Riunione si chiama con data, ora e titolo")
    func noteName() {
        #expect(VaultNaming.noteName(startedAt: startedAt, title: "Riunione", timeZone: rome) == "2026-10-04 1430 - Riunione")
    }

    @Test("i caratteri vietati da Obsidian nel titolo diventano spazi, senza spazi doppi", arguments: [
        ("Budget Q3: rivedere / approvare?", "Budget Q3 rivedere approvare"),
        ("Sprint #12 [retro] | team^", "Sprint 12 retro team"),
        ("  \"Kickoff\" <cliente> *  ", "Kickoff cliente"),
        (":/?", "Riunione"),
    ])
    func forbiddenCharacters(title: String, expected: String) {
        #expect(VaultNaming.noteName(startedAt: startedAt, title: title, timeZone: rome) == "2026-10-04 1430 - \(expected)")
    }

    @Test("se il nome è già usato si aggiunge il primo suffisso libero")
    func collisions() {
        let name = "2026-10-04 1430 - Riunione"

        #expect(VaultNaming.available(name, taken: []) == name)
        #expect(VaultNaming.available(name, taken: [name]) == "\(name) (2)")
        #expect(VaultNaming.available(name, taken: [name, "\(name) (2)"]) == "\(name) (3)")
        // Il file system del Mac non distingue maiuscole e minuscole.
        #expect(VaultNaming.available(name, taken: [name.lowercased()]) == "\(name) (2)")
    }

    @Test("il nome di un file scelto dall'utente perde i caratteri vietati da Obsidian", arguments: [
        ("Retro: sprint/12", "Retro sprint 12"),
        ("  1:1 #settimanale ", "1 1 settimanale"),
        ("???", nil),
    ] as [(String, String?)])
    func fileName(input: String, expected: String?) {
        #expect(VaultNaming.fileName(input) == expected)
    }
}
