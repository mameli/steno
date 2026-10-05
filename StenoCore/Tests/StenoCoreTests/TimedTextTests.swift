import Foundation
import Testing
import StenoCore

@Suite("Joining recognised tokens into sentences")
struct TimedTextTests {
    func token(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> TimedText {
        TimedText(text: text, start: start, end: end)
    }

    @Test("a sentence ends at its final punctuation, with the times of its first and last token")
    func punctuation() {
        let tokens = [
            token(" Ci", 0.5, 0.7), token("ao", 0.7, 0.9), token(" a", 0.9, 1.0), token(" tutti", 1.0, 1.4), token(".", 1.4, 1.5),
            token(" Come", 2.0, 2.3), token(" va", 2.3, 2.5), token("?", 2.5, 2.6),
        ]

        #expect(sentences(from: tokens) == [
            TimedText(text: "Ciao a tutti.", start: 0.5, end: 1.5),
            TimedText(text: "Come va?", start: 2.0, end: 2.6),
        ])
    }

    @Test("a long pause also ends a sentence, and the last one is kept without punctuation")
    func pause() {
        let tokens = [token(" sì", 0, 0.3), token(" no", 3, 3.2), token(" forse", 3.3, 3.6)]

        #expect(sentences(from: tokens) == [
            TimedText(text: "sì", start: 0, end: 0.3),
            TimedText(text: "no forse", start: 3, end: 3.6),
        ])
    }

    @Test("no tokens, no sentences")
    func empty() {
        #expect(sentences(from: []).isEmpty)
        #expect(sentences(from: [token(" ", 0, 0.1)]).isEmpty)
    }
}
