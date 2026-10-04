import Testing
import StenoCore

/// At 100 samples per second a half-second window is 50 samples.
@Suite("Finding speech ranges")
struct SpeechRangesTests {
    let sampleRate = 100.0

    /// `seconds` of audio: amplitude 0.1 inside the `loud` ranges, `quiet` elsewhere.
    func signal(seconds: Double, loud: [ClosedRange<Double>], quiet: Float = 0) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { index in
            let time = Double(index) / sampleRate
            return loud.contains { $0.contains(time) } ? (index.isMultiple(of: 2) ? 0.1 : -0.1) : quiet
        }
    }

    @Test("silence contains no speech")
    func silence() {
        #expect(speechRanges(in: signal(seconds: 10, loud: []), sampleRate: sampleRate).isEmpty)
    }

    @Test("a sentence becomes a range, with a quarter-second margin on each side")
    func singleBurst() {
        let samples = signal(seconds: 10, loud: [2.0...3.99])

        // Speech in the 2.0-4.0 s windows; 0.25 s margin: 1.75-4.25 s.
        #expect(speechRanges(in: samples, sampleRate: sampleRate) == [175..<425])
    }

    @Test("a pause under 2 seconds does not split the range, a longer one does")
    func gaps() {
        let samples = signal(seconds: 20, loud: [1.0...2.99, 4.5...5.99, 9.0...9.99])

        // 1.5 s pause between 3.0 and 4.5: one range. 3 s pause between 6.0 and 9.0: two ranges.
        #expect(speechRanges(in: samples, sampleRate: sampleRate) == [75..<625, 875..<1025])
    }

    @Test("faint audio below the threshold is not speech, even if it is not silence")
    func quietBackground() {
        // RMS 0.001: like a voice from another room or the echo residue measured in phase 1.
        let samples = signal(seconds: 10, loud: [5.0...5.99], quiet: 0.001)

        #expect(speechRanges(in: samples, sampleRate: sampleRate) == [475..<625])
    }
}
