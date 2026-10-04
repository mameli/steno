import AVFoundation
import StenoCore

/// Transcribes the Segments of a Meeting as they close and, at the stop, writes
/// `transcript.md` in the Recording folder.
actor MeetingTranscription {
    /// The Transcript written, the language used (`nil` if there was no speech)
    /// and the Segments that could not be transcribed.
    struct Finished {
        let url: URL
        let transcript: Transcript
        let language: String?
        let failedSegments: [String]
    }

    /// Result of a Segment saved next to the audio: a new Processing does not redo it.
    private struct CachedSegment: Codable {
        /// `nil` if the Segment contains no speech.
        let language: String?
        let utterances: [Utterance]
    }

    private static let languageDetectionSeconds = 30.0
    /// Below this much speech (e.g. a short "ok") detection is unreliable: the language is
    /// used for that Segment only and detection is tried again on the next one.
    private static let minimumSpeechToLockLanguage = 10.0

    private let transcriber: LocalTranscriber
    private let forcedLanguage: String?
    private var languageDetection: Task<String, Error>?
    /// Language detected on too little speech to lock it for the Meeting.
    private var provisionalLanguage: String?
    private var pending: [String: Task<[Utterance], Error>] = [:]

    /// `language` is `nil` to detect it automatically.
    init(transcriber: LocalTranscriber, language: String?) {
        self.transcriber = transcriber
        self.forcedLanguage = language
    }

    func segmentClosed(_ segment: Segment, in directory: URL) {
        startIfNeeded(segment, in: directory)
    }

    /// Transcribes the missing Segments, waits for those in progress and writes the Transcript.
    /// A failing Segment does not block the others: the Transcript comes out with a gap.
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
        let url = directory.appending(path: Transcript.recordingCopyFileName)
        let transcript = Transcript(utterances: utterances)
        try transcript.markdown.write(to: url, atomically: true, encoding: .utf8)
        let language: String? = if let forcedLanguage {
            forcedLanguage
        } else if let locked = try? await languageDetection?.value {
            locked
        } else {
            provisionalLanguage
        }
        return Finished(url: url, transcript: transcript, language: language, failedSegments: failed)
    }

    private func startIfNeeded(_ segment: Segment, in directory: URL) {
        guard pending[segment.fileName] == nil else { return }
        pending[segment.fileName] = Task { try await self.transcribe(segment, in: directory) }
    }

    private func transcribe(_ segment: Segment, in directory: URL) async throws -> [Utterance] {
        let cacheURL = directory.appending(path: segment.transcriptionCacheFileName)
        if let cached = try? JSONDecoder().decode(CachedSegment.self, from: Data(contentsOf: cacheURL)),
           cached.language == nil || forcedLanguage == nil || cached.language == forcedLanguage {
            if let language = cached.language, forcedLanguage == nil, languageDetection == nil {
                // Same language for the whole Meeting, even if some Segments come from the cache.
                languageDetection = Task { language }
            }
            return cached.utterances
        }

        let sampleRate = Recording.sampleRate
        let samples = try Self.loadSamples(directory.appending(path: segment.fileName))
        // Whisper only gets the speech ranges: on silence and faint audio (echo residue,
        // distant voices) it makes up sentences such as "Grazie.".
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

    /// One language per Meeting, detected once on up to 30 seconds of speech (silence
    /// confuses detection). It is locked only when there are at least 10 seconds of speech:
    /// on a short "ok" Whisper can pick the wrong language and then translate instead of transcribing.
    private func meetingLanguage(_ samples: [Float], speech ranges: [Range<Int>]) async throws -> String {
        if let forcedLanguage { return forcedLanguage }
        if let languageDetection {
            do {
                return try await languageDetection.value
            } catch {
                self.languageDetection = nil
                throw error
            }
        }
        let limit = Int(Self.languageDetectionSeconds * Recording.sampleRate)
        var speech: [Float] = []
        for range in ranges where speech.count < limit {
            speech += samples[range].prefix(limit - speech.count)
        }
        let detection = Task { [transcriber] in try await transcriber.detectLanguage(speech) }
        let isReliable = Double(speech.count) >= Self.minimumSpeechToLockLanguage * Recording.sampleRate
        if isReliable { languageDetection = detection }
        do {
            let language = try await detection.value
            if !isReliable { provisionalLanguage = language }
            return language
        } catch {
            if isReliable { languageDetection = nil }
            throw error
        }
    }

    /// Reads the Segment in 10-second blocks: a single read of minutes of AAC, with voice
    /// processing active in the same process, makes the macOS decoder spin forever.
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
        case .unreadableAudio(let file): String(localized: "Cannot read the audio of \(file).")
        }
    }
}
