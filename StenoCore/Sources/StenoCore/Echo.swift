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
