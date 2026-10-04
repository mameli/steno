import Testing
import StenoCore

@Suite("Etichetta del timer")
struct ElapsedLabelTests {
    @Test("sotto l'ora mostra minuti e secondi")
    func minutesAndSeconds() {
        #expect(elapsedLabel(754) == "12:34")
    }

    @Test("minuti e secondi hanno sempre due cifre", arguments: [
        (0.0, "00:00"),
        (7.0, "00:07"),
        (59.9, "00:59"),
    ])
    func zeroPadded(elapsed: Double, label: String) {
        #expect(elapsedLabel(elapsed) == label)
    }

    @Test("oltre l'ora aggiunge le ore senza zero iniziale")
    func hours() {
        #expect(elapsedLabel(3723) == "1:02:03")
    }
}
