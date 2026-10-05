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

    /// Where the model is, shown in the menu while it is not ready.
    enum ModelPhase: Equatable, Sendable {
        case notLoaded
        /// First use: the model (about 630 MB) is being downloaded.
        case downloading(fraction: Double)
        /// `firstTime` right after the download: macOS then prepares the model for the Neural
        /// Engine, which takes a few minutes once. Otherwise loading takes seconds.
        case loading(firstTime: Bool)
        case ready
    }

    static let model = "openai_whisper-large-v3-v20240930_turbo_632MB"

    static var modelsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Steno/Models", directoryHint: .isDirectory)
    }

    /// Meetings are in Italian or English: language detection picks only between these
    /// (a Template can still ask for a Summary in any language).
    static let supportedLanguages = ["it", "en"]

    /// Written next to the model once it is fully downloaded: a download interrupted halfway
    /// is resumed instead of being loaded.
    private static let downloadedMarker = ".steno-downloaded"

    /// Where WhisperKit puts the model under `modelsDirectory`.
    private static var modelFolder: URL {
        modelsDirectory.appending(path: "models/argmaxinc/whisperkit-coreml/\(model)", directoryHint: .isDirectory)
    }

    private var onPhase: @Sendable (ModelPhase) -> Void = { _ in }
    private var whisperKit: WhisperKit?
    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// `handler` is called from any thread whenever the model changes phase.
    func setPhaseHandler(_ handler: @escaping @Sendable (ModelPhase) -> Void) {
        onPhase = handler
    }

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
        do {
            var folder = Self.modelFolder
            let marker = folder.appending(path: Self.downloadedMarker)
            let needsDownload = !FileManager.default.fileExists(atPath: marker.path(percentEncoded: false))
            if needsDownload {
                try FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
                onPhase(.downloading(fraction: 0))
                let onPhase = onPhase
                folder = try await WhisperKit.download(variant: Self.model, downloadBase: Self.modelsDirectory) {
                    onPhase(.downloading(fraction: $0.fractionCompleted))
                }
                try Data().write(to: folder.appending(path: Self.downloadedMarker))
            }
            onPhase(.loading(firstTime: needsDownload))
            // The tokenizer is downloaded the first time too, into `downloadBase`.
            let loaded = try await WhisperKit(WhisperKitConfig(
                model: Self.model,
                downloadBase: Self.modelsDirectory,
                modelFolder: folder.path(percentEncoded: false),
                verbose: false,
                logLevel: .error,
                download: false
            ))
            whisperKit = loaded
            onPhase(.ready)
            return loaded
        } catch {
            onPhase(.notLoaded)
            throw error
        }
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
