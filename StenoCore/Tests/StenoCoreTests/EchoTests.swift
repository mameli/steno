import Testing
import StenoCore

@Suite("Removing the others' voice leaked into the microphone")
struct EchoTests {
    let others = [
        Utterance(track: .others, start: 0, end: 6, text: " Una cosa che capisce pure l'uomo della strada,"),
        Utterance(track: .others, start: 6, end: 11, text: " cioè non è che serve essere un esperto, la macchina ti parla."),
        Utterance(track: .others, start: 60, end: 64, text: " Passiamo al budget del trimestre."),
    ]

    @Test("Me sentences repeating what the others say at the same moment are echo")
    func echoRemoved() {
        let me = [
            Utterance(track: .me, start: 3.3, end: 4.3, text: " strada"),
            Utterance(track: .me, start: 4.3, end: 6.9, text: " non è che serve"),
            Utterance(track: .me, start: 6.9, end: 8.3, text: " essere un esperto"),
        ]

        #expect(removingEcho(others + me) == others)
    }

    @Test("what I say while the others talk stays")
    func overlappingSpeechKept() {
        let me = [Utterance(track: .me, start: 5, end: 8, text: " Scusa, ti interrompo un attimo sulla macchina.")]

        #expect(removingEcho(others + me) == others + me)
    }

    @Test("repeating the others' words later, e.g. quoting them, is not echo")
    func laterQuoteKept() {
        let me = [Utterance(track: .me, start: 120, end: 123, text: " Non è che serve essere un esperto.")]

        #expect(removingEcho(others + me) == others + me)
    }

    @Test("a short reply is kept even if the others say the same word at the same time")
    func shortReplyKept() {
        let me = [Utterance(track: .me, start: 61, end: 61.5, text: " Budget.")]

        #expect(removingEcho(others + me) == others + me)
    }
}
