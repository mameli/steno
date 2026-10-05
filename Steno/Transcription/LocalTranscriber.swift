import Foundation
@preconcurrency import WhisperKit

/// Local Whisper through WhisperKit: one model loaded at a time for the whole app (the one the
/// request asks for), one request at a time.
actor LocalTranscriber {
    /// Recognised in an audio buffer, with times relative to the start of the buffer.
    struct RecognizedText: Sendable {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    /// Where the model is, shown in the menu while it is not ready. The download is reported
    /// by `TranscriptionModels`.
    enum ModelPhase: Equatable, Sendable {
        case notLoaded
        /// `firstTime` right after the download: macOS then prepares the model for the Neural
        /// Engine, which takes a few minutes once. Otherwise loading takes seconds.
        case loading(TranscriptionModel, firstTime: Bool)
        case ready
    }

    /// Meetings are in Italian or English: language detection picks only between these
    /// (a Template can still ask for a Summary in any language).
    static let supportedLanguages = ["it", "en"]

    private let models: TranscriptionModels
    private var onPhase: @Sendable (ModelPhase) -> Void = { _ in }
    private var whisperKit: WhisperKit?
    private var loadedModel: TranscriptionModel?
    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(models: TranscriptionModels) {
        self.models = models
    }

    /// `handler` is called from any thread whenever the model changes phase.
    func setPhaseHandler(_ handler: @escaping @Sendable (ModelPhase) -> Void) {
        onPhase = handler
    }

    /// Downloads the model on first use and loads it in memory. Later calls are immediate.
    func prepare(_ model: TranscriptionModel) async throws {
        await acquire()
        defer { release() }
        _ = try await loaded(model)
    }

    func detectLanguage(_ samples: [Float], model: TranscriptionModel) async throws -> String {
        await acquire()
        defer { release() }
        let (_, probabilities) = try await loaded(model).detectLangauge(audioArray: samples)
        return Self.supportedLanguages.max {
            probabilities[$0, default: -.infinity] < probabilities[$1, default: -.infinity]
        }!
    }

    func transcribe(_ samples: [Float], language: String, model: TranscriptionModel) async throws -> [RecognizedText] {
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
        let results = try await loaded(model).transcribe(audioArray: samples, decodeOptions: options)
        return results.flatMap(\.segments).map {
            RecognizedText(start: TimeInterval($0.start), end: TimeInterval($0.end), text: $0.text)
        }
    }

    /// The model in memory, downloading and loading it if it is another one (only one is kept:
    /// the large ones take gigabytes).
    private func loaded(_ model: TranscriptionModel) async throws -> WhisperKit {
        if let whisperKit, loadedModel == model { return whisperKit }
        whisperKit = nil
        loadedModel = nil
        do {
            let (folder, downloadedNow) = try await models.ensureDownloaded(model)
            onPhase(.loading(model, firstTime: downloadedNow))
            // The tokenizer is downloaded the first time too, into the models folder.
            let loaded = try await WhisperKit(WhisperKitConfig(
                model: model.id,
                downloadBase: TranscriptionModels.directory,
                modelFolder: folder.path(percentEncoded: false),
                verbose: false,
                logLevel: .error,
                download: false
            ))
            whisperKit = loaded
            loadedModel = model
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
