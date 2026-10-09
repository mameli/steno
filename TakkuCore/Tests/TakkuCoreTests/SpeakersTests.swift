import Foundation
import Testing
import TakkuCore

@Suite("Telling the others apart in the Transcript")
struct SpeakersTests {
    @Test("each Others Utterance takes the voice speaking during it, numbered by first appearance")
    func numberedByFirstAppearance() {
        let utterances = [
            Utterance(track: .others, start: 0, end: 4, text: "Good morning everyone."),
            Utterance(track: .others, start: 5, end: 8, text: "Hi, I'm Giulia."),
            Utterance(track: .others, start: 9, end: 12, text: "Let's start."),
        ]
        let turns = [
            SpeakerTurn(voice: "S7", start: 0, end: 4.2),
            SpeakerTurn(voice: "S3", start: 4.8, end: 8.1),
            SpeakerTurn(voice: "S7", start: 8.9, end: 12),
        ]

        #expect(assigningSpeakers(to: utterances, turns: turns).map(\.speaker) == [1, 2, 1])
    }

    @Test("an Utterance across two voices takes the one speaking longest in it")
    func longestOverlapWins() {
        let utterances = [Utterance(track: .others, start: 10, end: 20, text: "Yes, exactly, and the budget is approved.")]
        let turns = [
            SpeakerTurn(voice: "A", start: 9, end: 12),
            SpeakerTurn(voice: "B", start: 12, end: 20),
        ]

        #expect(assigningSpeakers(to: utterances, turns: turns).map(\.speaker) == [1])
    }

    @Test("a short reply diarization did not hear takes the nearest voice within 2 seconds, otherwise none")
    func nearestTurnForUnheardReplies() {
        let utterances = [
            Utterance(track: .others, start: 0, end: 5, text: "Is that fine?"),
            Utterance(track: .others, start: 6, end: 6.4, text: "Ok."),
            Utterance(track: .others, start: 30, end: 30.4, text: "Yes."),
        ]
        let turns = [
            SpeakerTurn(voice: "A", start: 0, end: 5),
            SpeakerTurn(voice: "B", start: 6.8, end: 9),
        ]

        #expect(assigningSpeakers(to: utterances, turns: turns).map(\.speaker) == [1, 2, nil])
    }

    @Test("Me Utterances are left alone, also when the others talk at the same time")
    func meUntouched() {
        let utterances = [
            Utterance(track: .me, start: 0, end: 3, text: "Sorry, one question."),
            Utterance(track: .others, start: 1, end: 3, text: "Go ahead."),
        ]
        let turns = [SpeakerTurn(voice: "A", start: 0, end: 3)]

        #expect(assigningSpeakers(to: utterances, turns: turns).map(\.speaker) == [nil, 1])
    }

    @Test("a voice with no Utterance does not use up a number")
    func silentVoiceSkipped() {
        let utterances = [Utterance(track: .others, start: 10, end: 12, text: "Let's start.")]
        let turns = [
            SpeakerTurn(voice: "noise", start: 0, end: 1),
            SpeakerTurn(voice: "A", start: 10, end: 12),
        ]

        #expect(assigningSpeakers(to: utterances, turns: turns).map(\.speaker) == [1])
    }

    @Test("a paragraph holds one Speaker: a new voice starts a new paragraph with its own time")
    func paragraphsSplitBySpeaker() {
        let transcript = Transcript(utterances: [
            Utterance(track: .others, start: 0, end: 4, text: "Good morning everyone.", speaker: 1),
            Utterance(track: .others, start: 5, end: 8, text: "Shall we start?", speaker: 1),
            Utterance(track: .others, start: 9, end: 12, text: "Yes, go ahead.", speaker: 2),
            Utterance(track: .me, start: 13, end: 14, text: "Ok.", speaker: nil),
            Utterance(track: .others, start: 15, end: 16, text: "Hmm.", speaker: nil),
        ])

        #expect(transcript.markdown == """
            **[00:00] Speaker 1:** Good morning everyone. Shall we start?

            **[00:09] Speaker 2:** Yes, go ahead.

            **[00:13] Me:** Ok.

            **[00:15] Others:** Hmm.

            """)
    }

    @Test("the Transcript file in the Vault reads back with its Speakers")
    func parseSpeakers() {
        let original = Transcript(utterances: [
            Utterance(track: .others, start: 0, end: 4, text: "Good morning everyone.", speaker: 1),
            Utterance(track: .me, start: 5, end: 6, text: "Hi.", speaker: nil),
            Utterance(track: .others, start: 12, end: 14, text: "Let's start.", speaker: 12),
            Utterance(track: .others, start: 20, end: 21, text: "Hmm.", speaker: nil),
        ])
        let file = original.vaultFile(takkuID: UUID(), meetingNoteName: "2026-10-04 1430 - Meeting", language: "en")

        #expect(Transcript.parse(vaultFile: file).transcript.paragraphs == original.paragraphs)
    }
}
