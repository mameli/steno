import Foundation

/// Parametri della ricerca del parlato. Le soglie vengono dalle misure della fase 1:
/// silenzio ed eco residuo sotto 0,002 di RMS, la voce nel microfono oltre 0,05,
/// un video riprodotto a volume basso intorno a 0,008.
public enum SpeechDetection {
    public static let threshold: Float = 0.004
    public static let frameDuration: TimeInterval = 0.5
    public static let padding: TimeInterval = 0.25
    /// Le pause più brevi di così restano dentro il tratto: chi parla prende fiato.
    public static let maxPause: TimeInterval = 2
}

/// I tratti di `samples` che contengono parlato, come intervalli di indici.
///
/// L'audio si divide in finestre da mezzo secondo: quelle con RMS sopra soglia
/// sono parlato, le pause brevi vengono assorbite e ogni tratto si allarga di
/// un margine per non tagliare le parole.
public func speechRanges(in samples: [Float], sampleRate: Double) -> [Range<Int>] {
    let frame = Int(SpeechDetection.frameDuration * sampleRate)
    let padding = Int(SpeechDetection.padding * sampleRate)
    let maxPause = Int(SpeechDetection.maxPause * sampleRate)

    var ranges: [Range<Int>] = []
    for start in stride(from: 0, to: samples.count, by: frame) {
        let end = min(samples.count, start + frame)
        let meanSquare = samples[start..<end].reduce(0) { $0 + $1 * $1 } / Float(end - start)
        guard meanSquare.squareRoot() > SpeechDetection.threshold else { continue }

        if let last = ranges.last, start - last.upperBound < maxPause {
            ranges[ranges.count - 1] = last.lowerBound..<end
        } else {
            ranges.append(start..<end)
        }
    }
    return ranges.map { max(0, $0.lowerBound - padding)..<min(samples.count, $0.upperBound + padding) }
}
