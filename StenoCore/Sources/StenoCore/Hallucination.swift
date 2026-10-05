import Foundation

/// Sentences Whisper makes up on a short noise (a click, a notification sound): it learned
/// them from the end of subtitled videos. Lowercased, without final punctuation.
private let stockSentences: Set<String> = [
    "grazie", "grazie a tutti", "grazie mille", "grazie per la visione", "grazie per l'attenzione",
    "sottotitoli creati dalla comunità amara.org", "sottotitoli a cura di qtss",
    "thank you", "thank you very much", "thanks for watching", "thank you for watching", "you", "bye",
]

/// Speech ranges longer than this are real speech even when the text is a stock sentence.
private let maxHallucinationSeconds: TimeInterval = 3

/// True when everything recognised in a speech range is one stock sentence and the range is
/// short: a real "Grazie." from the others is lost, a made-up one on a noise no longer appears.
public func isLikelyHallucination(_ texts: [String], speechDuration: TimeInterval) -> Bool {
    guard speechDuration <= maxHallucinationSeconds else { return false }
    let text = texts.joined(separator: " ")
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    return stockSentences.contains(text)
}
