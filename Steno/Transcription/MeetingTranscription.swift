import AVFoundation
import StenoCore

/// Trascrive i segmenti di una Riunione man mano che si chiudono e allo stop
/// scrive `trascrizione.md` nella cartella della Registrazione.
actor MeetingTranscription {
    /// La Trascrizione scritta, la lingua usata (`nil` se non c'era parlato)
    /// e i segmenti che non è stato possibile trascrivere.
    struct Finished {
        let url: URL
        let transcript: Transcript
        let language: String?
        let failedSegments: [String]
    }

    /// Risultato di un segmento salvato accanto all'audio: una nuova Elaborazione non lo rifà.
    private struct CachedSegment: Codable {
        /// `nil` se il segmento non contiene parlato.
        let language: String?
        let utterances: [Utterance]
    }

    private static let languageDetectionSeconds = 30.0

    private let transcriber: LocalTranscriber
    private let forcedLanguage: String?
    private var languageDetection: Task<String, Error>?
    private var pending: [String: Task<[Utterance], Error>] = [:]

    /// `language` è `nil` per rilevarla in automatico.
    init(transcriber: LocalTranscriber, language: String?) {
        self.transcriber = transcriber
        self.forcedLanguage = language
    }

    func segmentClosed(_ segment: Segment, in directory: URL) {
        startIfNeeded(segment, in: directory)
    }

    /// Trascrive i segmenti mancanti, aspetta quelli in corso e scrive la Trascrizione.
    /// Un segmento che fallisce non blocca gli altri: la Trascrizione esce con un buco.
    func finish(_ recording: Recording, in directory: URL) async throws -> Finished {
        for segment in recording.segments {
            startIfNeeded(segment, in: directory)
        }
        var utterances: [Utterance] = []
        var failed: [String] = []
        for segment in recording.segments {
            do {
                utterances += try await pending[segment.fileName]!.value
            } catch {
                failed.append("\(segment.fileName): \(error.localizedDescription)")
                pending[segment.fileName] = nil
            }
        }
        let url = directory.appending(path: "trascrizione.md")
        let transcript = Transcript(utterances: utterances)
        try transcript.markdown.write(to: url, atomically: true, encoding: .utf8)
        let language: String? = if let forcedLanguage { forcedLanguage } else { try? await languageDetection?.value }
        return Finished(url: url, transcript: transcript, language: language, failedSegments: failed)
    }

    private func startIfNeeded(_ segment: Segment, in directory: URL) {
        guard pending[segment.fileName] == nil else { return }
        pending[segment.fileName] = Task { try await self.transcribe(segment, in: directory) }
    }

    private func transcribe(_ segment: Segment, in directory: URL) async throws -> [Utterance] {
        let cacheURL = directory.appending(path: segment.fileName + ".json")
        if let cached = try? JSONDecoder().decode(CachedSegment.self, from: Data(contentsOf: cacheURL)),
           cached.language == nil || forcedLanguage == nil || cached.language == forcedLanguage {
            if let language = cached.language, forcedLanguage == nil, languageDetection == nil {
                // Stessa lingua per tutta la Riunione, anche se parte dei segmenti viene dalla cache.
                languageDetection = Task { language }
            }
            return cached.utterances
        }

        let sampleRate = Recording.sampleRate
        let samples = try Self.loadSamples(directory.appending(path: segment.fileName))
        // Whisper riceve solo i tratti con parlato: sul silenzio e sull'audio debole
        // (eco residuo, voci lontane) inventa frasi come "Grazie.".
        let ranges = speechRanges(in: samples, sampleRate: sampleRate)
        guard !ranges.isEmpty else {
            try JSONEncoder().encode(CachedSegment(language: nil, utterances: [])).write(to: cacheURL)
            return []
        }

        let language = try await meetingLanguage(samples, speech: ranges)
        var utterances: [Utterance] = []
        for range in ranges {
            let offset = segment.start + Double(range.lowerBound) / sampleRate
            let recognized = try await transcriber.transcribe(Array(samples[range]), language: language)
            utterances += recognized.map {
                Utterance(track: segment.track, start: offset + $0.start, end: offset + $0.end, text: $0.text)
            }
        }
        try JSONEncoder().encode(CachedSegment(language: language, utterances: utterances)).write(to: cacheURL)
        return utterances
    }

    /// Una sola lingua per Riunione, rilevata una volta sui primi 30 secondi di parlato
    /// del primo segmento che ne ha (il silenzio confonde il rilevamento).
    private func meetingLanguage(_ samples: [Float], speech ranges: [Range<Int>]) async throws -> String {
        if let forcedLanguage { return forcedLanguage }
        if languageDetection == nil {
            let limit = Int(Self.languageDetectionSeconds * Recording.sampleRate)
            var speech: [Float] = []
            for range in ranges where speech.count < limit {
                speech += samples[range].prefix(limit - speech.count)
            }
            languageDetection = Task { [transcriber] in try await transcriber.detectLanguage(speech) }
        }
        do {
            return try await languageDetection!.value
        } catch {
            languageDetection = nil
            throw error
        }
    }

    /// Legge il segmento a blocchi da 10 secondi: una lettura unica di minuti di AAC, con il
    /// voice processing attivo nello stesso processo, fa girare a vuoto il decoder di macOS.
    private static func loadSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let blockFrames = AVAudioFrameCount(10 * Recording.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: blockFrames) else {
            throw TranscriptionError.unreadableAudio(url.lastPathComponent)
        }
        var samples: [Float] = []
        samples.reserveCapacity(Int(file.length))
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: blockFrames)
            guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }
        return samples
    }
}

enum TranscriptionError: LocalizedError {
    case unreadableAudio(String)

    var errorDescription: String? {
        switch self {
        case .unreadableAudio(let file): "Impossibile leggere l'audio di \(file)."
        }
    }
}
