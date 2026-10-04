import Foundation
@preconcurrency import WhisperKit

/// Local Whisper through WhisperKit: a single model loaded for the whole app,
/// one request at a time.
actor LocalTranscriber {
    /// Recognised in an audio buffer, with times relative to the start of the buffer.
    struct RecognizedText: Sendable {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    static let model = "openai_whisper-large-v3-v20240930_turbo_632MB"

    static var modelsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Steno/Models", directoryHint: .isDirectory)
    }

    /// Meetings are in Italian or English: language detection picks only between these
    /// (a Template can still ask for a Summary in any language).
    static let supportedLanguages = ["it", "en"]

    private var whisperKit: WhisperKit?
    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Downloads the model on first use and loads it in memory. Later calls are immediate.
    func prepare() async throws {
        await acquire()
        defer { release() }
        _ = try await loadedWhisperKit()
    }

    func detectLanguage(_ samples: [Float]) async throws -> String {
        await acquire()
        defer { release() }
        let (_, probabilities) = try await loadedWhisperKit().detectLangauge(audioArray: samples)
        return Self.supportedLanguages.max {
            probabilities[$0, default: -.infinity] < probabilities[$1, default: -.infinity]
        }!
    }

    func transcribe(_ samples: [Float], language: String) async throws -> [RecognizedText] {
        await acquire()
        defer { release() }
        // Speech is already guaranteed by the ranges MeetingTranscription passes in: Whisper's
        // "no speech" threshold would only drop degraded audio (voices coming through a phone).
        let options = DecodingOptions(
            language: language,
            detectLanguage: false,
            skipSpecialTokens: true,
            noSpeechThreshold: nil,
            chunkingStrategy: .vad
        )
        let results = try await loadedWhisperKit().transcribe(audioArray: samples, decodeOptions: options)
        return results.flatMap(\.segments).map {
            RecognizedText(start: TimeInterval($0.start), end: TimeInterval($0.end), text: $0.text)
        }
    }

    private func loadedWhisperKit() async throws -> WhisperKit {
        if let whisperKit { return whisperKit }
        try FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
        let loaded = try await WhisperKit(WhisperKitConfig(
            model: Self.model,
            downloadBase: Self.modelsDirectory,
            verbose: false,
            logLevel: .error,
            download: true
        ))
        whisperKit = loaded
        return loaded
    }

    // WhisperKit does not guarantee safe concurrent requests: one at a time, in arrival order.

    private func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            isBusy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
