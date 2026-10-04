import AVFoundation
import StenoCore

/// Riceve i buffer di una sorgente audio con l'host time del loro primo frame.
typealias AudioBufferHandler = @Sendable (AVAudioPCMBuffer, UInt64) -> Void

/// Converte l'audio di una Traccia in mono 16 kHz e lo scrive in segmenti AAC.
///
/// `write` viene chiamato dal thread della sorgente audio, `finish` dal main
/// thread dopo che la sorgente è stata fermata: il lock serializza i due.
final class SegmentedTrackWriter: @unchecked Sendable {
    /// I segmenti scritti e, se c'è stato, l'errore che ha interrotto la Traccia.
    struct Outcome {
        let segments: [Segment]
        let error: Error?
    }

    static let sampleRate: Double = 16_000

    private static var fileSettings: [String: Any] {
        [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1]
    }

    private let track: Track
    private let directory: URL
    private let meetingStartHostTime: UInt64
    private let segmentDuration: TimeInterval
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
    )!
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var segmenter: TrackSegmenter?
    private var file: AVAudioFile?
    private var fileIndex: Int?
    private var firstError: Error?
    private var isFinished = false

    init(track: Track, directory: URL, meetingStartHostTime: UInt64, segmentDuration: TimeInterval) {
        self.track = track
        self.directory = directory
        self.meetingStartHostTime = meetingStartHostTime
        self.segmentDuration = segmentDuration
    }

    /// Elenco dei segmenti aggiornato a ogni apertura: se l'app va in crash
    /// prima dello stop, gli offset restano su disco.
    var segmentsFileURL: URL {
        directory.appending(path: "\(track.rawValue)-segmenti.json")
    }

    func write(_ buffer: AVAudioPCMBuffer, hostTime: UInt64) {
        lock.withLock {
            // Un buffer può arrivare dal thread audio anche dopo lo stop.
            guard !isFinished, firstError == nil else { return }
            do {
                try writeLocked(buffer, hostTime: hostTime)
            } catch {
                firstError = error
            }
        }
    }

    func finish() -> Outcome {
        lock.withLock {
            isFinished = true
            file?.close()
            file = nil
            return Outcome(segments: segmenter?.segments ?? [], error: firstError)
        }
    }

    private func writeLocked(_ buffer: AVAudioPCMBuffer, hostTime: UInt64) throws {
        let converted = try convert(buffer)
        guard converted.frameLength > 0 else { return }

        if segmenter == nil {
            segmenter = TrackSegmenter(
                track: track,
                sampleRate: Self.sampleRate,
                trackStart: secondsSinceMeetingStart(hostTime),
                segmentDuration: segmentDuration
            )
        }
        let segment = segmenter!.place(frameCount: Int(converted.frameLength))
        if segment.index != fileIndex {
            file?.close()
            file = try AVAudioFile(
                forWriting: directory.appending(path: segment.fileName),
                settings: Self.fileSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            fileIndex = segment.index
            try JSONEncoder().encode(segmenter!.segments).write(to: segmentsFileURL, options: .atomic)
        }
        try file!.write(from: converted)
    }

    private func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if converter?.inputFormat != buffer.format {
            guard let newConverter = AVAudioConverter(from: buffer.format, to: outputFormat) else {
                throw CaptureError.unsupportedFormat(buffer.format.description)
            }
            if buffer.format.channelCount > 2 {
                // Voice processing: il canale 0 è quello già ripulito dall'eco.
                newConverter.channelMap = [0]
            } else {
                newConverter.downmix = true
            }
            converter = newConverter
        }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)!

        var consumed = false
        var conversionError: NSError?
        let status = converter!.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error, let conversionError { throw conversionError }
        return output
    }

    private func secondsSinceMeetingStart(_ hostTime: UInt64) -> TimeInterval {
        guard hostTime > meetingStartHostTime else { return 0 }
        return AVAudioTime.seconds(forHostTime: hostTime - meetingStartHostTime)
    }
}
