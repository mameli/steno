import Foundation

/// A piece of recognised text with its times, in seconds from the start of the audio.
public struct TimedText: Equatable, Sendable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// A pause this long between two tokens ends the sentence even without punctuation.
private let sentencePause: TimeInterval = 1.5
private let sentenceEnds: Set<Character> = [".", "?", "!", "…"]

/// Joins the tokens of a recogniser that times each token (Parakeet) into sentences, so the
/// Transcript gets Utterances like Whisper's. Tokens carry their own leading spaces.
public func sentences(from tokens: [TimedText]) -> [TimedText] {
    var result: [TimedText] = []
    var current: [TimedText] = []

    func close() {
        let text = current.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = current.first, let last = current.last, !text.isEmpty {
            result.append(TimedText(text: text, start: first.start, end: last.end))
        }
        current = []
    }

    for token in tokens {
        if let previous = current.last, token.start - previous.end >= sentencePause {
            close()
        }
        current.append(token)
        if let last = token.text.last, sentenceEnds.contains(last) {
            close()
        }
    }
    close()
    return result
}
