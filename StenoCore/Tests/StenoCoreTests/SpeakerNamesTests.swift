import Foundation
import Testing
import StenoCore

@Suite("Speaker names and invited participants")
struct SpeakerNamesTests {
    let stenoID = UUID(uuidString: "6F1C2A00-0000-4000-8000-000000000001")!

    func note(_ frontmatter: String) -> MeetingNote {
        MeetingNote(content: "---\nsteno_id: \(stenoID.uuidString)\n\(frontmatter)\n---\nBody")
    }

    @Test("the user names Speakers in the frontmatter with `Speaker N = Name`; other entries are ignored")
    func speakerNames() {
        let names = note("""
            speakers:
              - Speaker 1 = Mario Rossi
              - "speaker 3=Anna Bianchi "
              - Speaker 1 = Someone else
              - Mario = Speaker 2
              - Speaker 4 =
            tags: [meeting]
            """).speakerNames

        #expect(names == [1: "Mario Rossi", 3: "Anna Bianchi"])
    }

    @Test("without the key there are no names; an inline list works too")
    func speakerNamesInline() {
        #expect(note("tags: [meeting]").speakerNames.isEmpty)
        #expect(note("speakers: [Speaker 2 = Luca Verdi]").speakerNames == [2: "Luca Verdi"])
    }

    let transcript = Transcript(utterances: [
        Utterance(track: .others, start: 0, end: 4, text: "Good morning.", speaker: 1),
        Utterance(track: .me, start: 5, end: 8, text: "Hi."),
        Utterance(track: .others, start: 10, end: 12, text: "Hello.", speaker: 2),
        Utterance(track: .others, start: 40, end: 44, text: "Ok.", speaker: nil),
    ])

    @Test("a named Speaker shows as `Name (Speaker N)` in the Transcript, the others keep the number")
    func naming() {
        let named = transcript.naming([1: "Mario Rossi", 7: "Nobody"])

        #expect(named.markdown == """
            **[00:00] Mario Rossi (Speaker 1):** Good morning.

            **[00:05] Me:** Hi.

            **[00:10] Speaker 2:** Hello.

            **[00:40] Others:** Ok.

            """)
        #expect(named.hasNamedSpeakers)
        #expect(!transcript.hasNamedSpeakers)
    }

    @Test("a named Transcript reads back with its numbers and names")
    func parseNamed() {
        let file = transcript.naming([1: "Mario Rossi"]).vaultFile(stenoID: stenoID, meetingNoteName: "Note", language: "it")

        let (parsed, _) = Transcript.parse(vaultFile: file)

        #expect(parsed.paragraphs[0] == Paragraph(track: .others, start: 0, text: "Good morning.", speaker: 1, name: "Mario Rossi"))
        #expect(parsed.paragraphs[2] == Paragraph(track: .others, start: 10, text: "Hello.", speaker: 2))
    }

    @Test("relabeling the Vault file changes only the Speakers' labels, by number, with the names of now")
    func relabeling() {
        let file = """
            ---
            steno_id: 1
            ---
            **[00:00] Mario Rossi (Speaker 1):** Good morning.
            (fixed by hand)

            **[00:05] Me:** Hi.

            **[1:00:10] Speaker 2:** ⭐ Hello.
            """

        #expect(Transcript.relabeling(vaultFile: file, names: [1: "Marco Rossi", 2: "Anna Bianchi"]) == """
            ---
            steno_id: 1
            ---
            **[00:00] Marco Rossi (Speaker 1):** Good morning.
            (fixed by hand)

            **[00:05] Me:** Hi.

            **[1:00:10] Anna Bianchi (Speaker 2):** ⭐ Hello.
            """)
        #expect(Transcript.relabeling(vaultFile: file, names: [:])?.contains("**[00:00] Speaker 1:** Good morning.") == true)
        #expect(Transcript.relabeling(vaultFile: file, names: [1: "Mario Rossi"]) == nil)
    }
}
