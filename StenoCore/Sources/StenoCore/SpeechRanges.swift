import Foundation

/// Speech detection parameters. The thresholds come from the phase 1 measurements:
/// silence and echo residue below 0.002 RMS, a voice into the microphone above 0.05,
/// a video played at low volume around 0.008.
public enum SpeechDetection {
    public static let threshold: Float = 0.004
    public static let frameDuration: TimeInterval = 0.5
    public static let padding: TimeInterval = 0.25
    /// Pauses shorter than this stay inside the range: speakers take a breath.
    public static let maxPause: TimeInterval = 2
}

/// The ranges of `samples` that contain speech, as index ranges.
///
/// Audio is split into half-second windows: those with RMS above the threshold are
/// speech, short pauses are absorbed and every range is widened by a margin so no
/// word is cut.
public func speechRanges(in samples: [Float], sampleRate: Double) -> [Range<Int>] {
    let frame = Int(SpeechDetection.frameDuration * sampleRate)
    let padding = Int(SpeechDetection.padding * sampleRate)
    let maxPause = Int(SpeechDetection.maxPause * sampleRate)

    var ranges: [Range<Int>] = []
    for start in stride(from: 0, to: samples.count, by: frame) {
        let end = min(samples.count, start + frame)
        guard isLoud(samples[start..<end]) else { continue }

        if let last = ranges.last, start - last.upperBound < maxPause {
            ranges[ranges.count - 1] = last.lowerBound..<end
        } else {
            ranges.append(start..<end)
        }
    }
    return ranges.map { max(0, $0.lowerBound - padding)..<min(samples.count, $0.upperBound + padding) }
}

/// Seconds of actual sound in `range` (a range returned by `speechRanges`): only the windows
/// above the threshold count, not the pauses absorbed into the range nor its margins.
public func speechSeconds(in samples: [Float], range: Range<Int>, sampleRate: Double) -> TimeInterval {
    let frame = Int(SpeechDetection.frameDuration * sampleRate)
    // Same windows as `speechRanges`: they start at multiples of `frame`.
    let firstWindow = (range.lowerBound + frame - 1) / frame * frame
    let loudWindows = stride(from: firstWindow, to: range.upperBound, by: frame).filter { start in
        isLoud(samples[start..<min(samples.count, start + frame)])
    }
    return Double(loudWindows.count) * SpeechDetection.frameDuration
}

private func isLoud(_ window: ArraySlice<Float>) -> Bool {
    let meanSquare = window.reduce(0) { $0 + $1 * $1 } / Float(window.count)
    return meanSquare.squareRoot() > SpeechDetection.threshold
}
