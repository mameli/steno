import Foundation

/// Me sentences closer than this belong to the same run, compared as a whole: Whisper splits
/// the leaked echo into fragments too short to judge one by one.
private let maxPauseInRun: TimeInterval = 2
/// Echo arrives at once, but Whisper's timestamps inside a speech range drift by a few seconds.
private let timeTolerance: TimeInterval = 5
/// Shorter runs ("ok", "sì") are kept: the same word at the same moment can be a real reply.
private let minWords = 3
private let minSharedFraction = 0.8

/// Removes from the Me Track the others' voice leaked into the microphone (speakers without
/// headphones, while echo cancellation is still adapting): a run of Me Utterances whose words
/// almost all appear, in the same order, in what the others say at the same moment.
public func removingEcho(_ utterances: [Utterance]) -> [Utterance] {
    let others = utterances.filter { $0.track == .others }.sorted { $0.start < $1.start }
    let me = utterances.indices.filter { utterances[$0].track == .me }.sorted { utterances[$0].start < utterances[$1].start }

    var runs: [[Int]] = []
    for index in me {
        if let last = runs.last?.last, utterances[index].start - utterances[last].end <= maxPauseInRun {
            runs[runs.count - 1].append(index)
        } else {
            runs.append([index])
        }
    }

    var echo = Set<Int>()
    for run in runs {
        let meWords = run.flatMap { words(utterances[$0].text) }
        guard meWords.count >= minWords else { continue }
        let from = utterances[run.first!].start - timeTolerance
        let to = utterances[run.last!].end + timeTolerance
        let othersWords = others.filter { $0.end >= from && $0.start <= to }.flatMap { words($0.text) }
        if Double(commonSubsequenceLength(meWords, othersWords)) >= minSharedFraction * Double(meWords.count) {
            echo.formUnion(run)
        }
    }
    return utterances.indices.filter { !echo.contains($0) }.map { utterances[$0] }
}

/// My voice into my microphone peaks between -10 and -25 dBFS; what echo cancellation leaves of
/// the others' voice peaks around -40, loud enough for the speech ranges and turned into random
/// words ("The five.", "Oh yeah") in any language. Measured on 13 real Meetings: 25 dB below the
/// loudest Me sentence removes that residue and keeps the faintest real replies by over 10 dB.
private let maxBelowLoudest = 25.0

/// Removes Me Utterances fainter than the loudest Me one by more than 25 dB: the others' voice
/// left in the microphone by echo cancellation, too garbled for `removingEcho` to match their
/// words. The reference is the loudest one, not a typical one, because in a Meeting where I
/// barely speak most Me Utterances are residue. A `nil` level (not measured) keeps the Utterance.
public func removingEchoResidue(_ measured: [(utterance: Utterance, level: Double?)]) -> [Utterance] {
    let loudest = measured.filter { $0.utterance.track == .me }.compactMap(\.level).max()
    return measured.filter { item in
        guard item.utterance.track == .me, let loudest, let level = item.level else { return true }
        return level >= loudest - maxBelowLoudest
    }.map(\.utterance)
}

/// The loudness of a stretch of audio: the RMS of its loudest 100 ms (windows every 50 ms),
/// in dBFS. A stretch shorter than 100 ms is one window.
public func peakLevel(of samples: ArraySlice<Float>, sampleRate: Double) -> Double {
    let window = Int(0.1 * sampleRate)
    let hop = window / 2
    var loudest: Float = 0
    var start = samples.startIndex
    repeat {
        let slice = samples[start..<min(samples.endIndex, start + window)]
        if !slice.isEmpty {
            loudest = max(loudest, slice.reduce(0) { $0 + $1 * $1 } / Float(slice.count))
        }
        start += hop
    } while start + window <= samples.endIndex
    return 10 * log10(Double(loudest) + 1e-12)
}

private func words(_ text: String) -> [String] {
    text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
}

/// Length of the longest sequence of words found in both, in the same order.
private func commonSubsequenceLength(_ a: [String], _ b: [String]) -> Int {
    guard !a.isEmpty, !b.isEmpty else { return 0 }
    var previous = [Int](repeating: 0, count: b.count + 1)
    for wordA in a {
        var current = [Int](repeating: 0, count: b.count + 1)
        for (j, wordB) in b.enumerated() {
            current[j + 1] = wordA == wordB ? previous[j] + 1 : max(previous[j + 1], current[j])
        }
        previous = current
    }
    return previous[b.count]
}
