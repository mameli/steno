import AVFoundation
import StenoCore

/// Registra le due Tracce di una Riunione nella sua cartella e ne salva il manifesto.
@MainActor
final class MeetingRecorder {
    private struct Active {
        let meetingID: UUID
        let directory: URL
        let startedAt: Date
        let me: SegmentedTrackWriter
        let others: SegmentedTrackWriter
    }

    /// Una Registrazione appena avviata: l'identificativo è lo `steno_id` della Riunione.
    struct Started {
        let meetingID: UUID
        let directory: URL
    }

    /// Una Registrazione chiusa. `errors` elenca le Tracce che si sono interrotte prima dello stop.
    struct Stopped {
        let directory: URL
        let recording: Recording
        let errors: [String]
    }

    private let microphone = MicrophoneCapture()
    private let systemAudio = SystemAudioCapture()
    private var active: Active?

    static var meetingsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Steno/Riunioni", directoryHint: .isDirectory)
    }

    private static var segmentDuration: TimeInterval {
        #if DEBUG
        // `--args -segmentSeconds 5` per provare il cambio di segmento senza aspettare 5 minuti.
        let override = UserDefaults.standard.double(forKey: "segmentSeconds")
        if override > 0 { return override }
        #endif
        return TrackSegmenter.defaultSegmentDuration
    }

    func start(
        at startedAt: Date, echoCancellation: Bool, onSegmentClosed: @escaping SegmentClosedHandler
    ) throws -> Started {
        let meetingID = UUID()
        let directory = Self.meetingsDirectory.appending(path: meetingID.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let hostTime = mach_absolute_time()
        func writer(for track: Track) -> SegmentedTrackWriter {
            SegmentedTrackWriter(
                track: track,
                directory: directory,
                meetingStartHostTime: hostTime,
                segmentDuration: Self.segmentDuration,
                onSegmentClosed: onSegmentClosed
            )
        }
        let me = writer(for: .me)
        let others = writer(for: .others)

        do {
            // Prima il tap di sistema, poi il microfono: il voice processing
            // riconfigura i dispositivi audio quando parte.
            try systemAudio.start { buffer, time in others.write(buffer, hostTime: time) }
            try microphone.start(echoCancellation: echoCancellation) { buffer, time in me.write(buffer, hostTime: time) }
        } catch {
            microphone.stop()
            systemAudio.stop()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        active = Active(meetingID: meetingID, directory: directory, startedAt: startedAt, me: me, others: others)
        return Started(meetingID: meetingID, directory: directory)
    }

    /// Ferma la cattura, chiude i segmenti e scrive `riunione.json` con quello che c'è,
    /// anche se una Traccia si è interrotta.
    func stop(at endedAt: Date) throws -> Stopped {
        guard let active else { preconditionFailure("stop senza una Registrazione attiva") }
        self.active = nil
        microphone.stop()
        systemAudio.stop()

        let outcomes = [(Track.me, active.me.finish()), (Track.others, active.others.finish())]
        let recording = Recording(
            meetingID: active.meetingID,
            startedAt: active.startedAt,
            endedAt: endedAt,
            segments: outcomes.flatMap { $0.1.segments }
        )
        try recording.save(to: active.directory.appending(path: "riunione.json"))

        let errors = outcomes.compactMap { track, outcome in
            outcome.error.map { "Traccia \(track.rawValue): \($0.localizedDescription)" }
        }
        return Stopped(directory: active.directory, recording: recording, errors: errors)
    }
}
