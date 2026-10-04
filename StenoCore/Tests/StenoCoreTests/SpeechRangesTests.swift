import Testing
import StenoCore

/// Con 100 campioni al secondo una finestra da mezzo secondo è di 50 campioni.
@Suite("Ricerca dei tratti con parlato")
struct SpeechRangesTests {
    let sampleRate = 100.0

    /// `seconds` di audio: ampiezza 0,1 negli intervalli `loud`, `quiet` altrove.
    func signal(seconds: Double, loud: [ClosedRange<Double>], quiet: Float = 0) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { index in
            let time = Double(index) / sampleRate
            return loud.contains { $0.contains(time) } ? (index.isMultiple(of: 2) ? 0.1 : -0.1) : quiet
        }
    }

    @Test("il silenzio non contiene parlato")
    func silence() {
        #expect(speechRanges(in: signal(seconds: 10, loud: []), sampleRate: sampleRate).isEmpty)
    }

    @Test("una frase diventa un tratto, con un quarto di secondo di margine per lato")
    func singleBurst() {
        let samples = signal(seconds: 10, loud: [2.0...3.99])

        // Parlato nelle finestre 2,0-4,0 s; margine 0,25 s: 1,75-4,25 s.
        #expect(speechRanges(in: samples, sampleRate: sampleRate) == [175..<425])
    }

    @Test("una pausa sotto i 2 secondi non spezza il tratto, una più lunga sì")
    func gaps() {
        let samples = signal(seconds: 20, loud: [1.0...2.99, 4.5...5.99, 9.0...9.99])

        // Pausa di 1,5 s tra 3,0 e 4,5: un tratto solo. Pausa di 3 s tra 6,0 e 9,0: due tratti.
        #expect(speechRanges(in: samples, sampleRate: sampleRate) == [75..<625, 875..<1025])
    }

    @Test("l'audio debole sotto soglia non è parlato, anche se non è silenzio")
    func quietBackground() {
        // RMS 0,001: come la voce da un'altra stanza o l'eco residuo misurati nella fase 1.
        let samples = signal(seconds: 10, loud: [5.0...5.99], quiet: 0.001)

        #expect(speechRanges(in: samples, sampleRate: sampleRate) == [475..<625])
    }
}
