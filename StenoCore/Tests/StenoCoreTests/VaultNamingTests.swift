import Foundation
import Testing
import StenoCore

@Suite("File names in the Vault")
struct VaultNamingTests {
    let rome = TimeZone(identifier: "Europe/Rome")!
    /// 4 October 2026, 14:30 in Rome.
    let startedAt = Date(timeIntervalSince1970: 1_791_117_000)

    @Test("the Meeting note is named with date, time and title")
    func noteName() {
        #expect(VaultNaming.noteName(startedAt: startedAt, title: "Meeting", timeZone: rome) == "2026-10-04 1430 - Meeting")
    }

    @Test("characters Obsidian forbids in the title become spaces, without double spaces", arguments: [
        ("Budget Q3: review / approve?", "Budget Q3 review approve"),
        ("Sprint #12 [retro] | team^", "Sprint 12 retro team"),
        ("  \"Kickoff\" <client> *  ", "Kickoff client"),
        (":/?", "Meeting"),
    ])
    func forbiddenCharacters(title: String, expected: String) {
        #expect(VaultNaming.noteName(startedAt: startedAt, title: title, timeZone: rome) == "2026-10-04 1430 - \(expected)")
    }

    @Test("if the name is taken the first free suffix is added")
    func collisions() {
        let name = "2026-10-04 1430 - Meeting"

        #expect(VaultNaming.available(name, taken: []) == name)
        #expect(VaultNaming.available(name, taken: [name]) == "\(name) (2)")
        #expect(VaultNaming.available(name, taken: [name, "\(name) (2)"]) == "\(name) (3)")
        // The Mac file system does not distinguish upper and lower case.
        #expect(VaultNaming.available(name, taken: [name.lowercased()]) == "\(name) (2)")
    }

    @Test("a file name chosen by the user loses the characters Obsidian forbids", arguments: [
        ("Retro: sprint/12", "Retro sprint 12"),
        ("  1:1 #weekly ", "1 1 weekly"),
        ("???", nil),
    ] as [(String, String?)])
    func fileName(input: String, expected: String?) {
        #expect(VaultNaming.fileName(input) == expected)
    }
}
