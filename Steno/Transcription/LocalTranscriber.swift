import Foundation
@preconcurrency import WhisperKit

/// Whisper locale tramite WhisperKit: un solo modello caricato per tutta l'app,
/// una richiesta alla volta.
actor LocalTranscriber {
    /// Riconosciuto in un buffer audio, con tempi relativi all'inizio del buffer.
    struct RecognizedText: Sendable {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    static let model = "openai_whisper-large-v3-v20240930_turbo_632MB"

    static var modelsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Steno/Modelli", directoryHint: .isDirectory)
    }

    /// Le Riunioni sono in italiano o in inglese: la lingua si sceglie solo tra queste.
    static let supportedLanguages = ["it", "en"]

    private var whisperKit: WhisperKit?
    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Scarica il modello al primo uso e lo carica in memoria. Le chiamate successive sono immediate.
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
        // Il parlato è già garantito dai tratti passati da MeetingTranscription: la soglia
        // "nessun parlato" di Whisper scarterebbe solo l'audio degradato (voci passate da un telefono).
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

    // WhisperKit non garantisce richieste concorrenti sicure: una alla volta, in ordine d'arrivo.

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
