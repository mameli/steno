import AVFoundation

/// Cattura la Traccia Io dal microfono di default.
@MainActor
final class MicrophoneCapture {
    private let engine = AVAudioEngine()

    func start(
        echoCancellation: Bool,
        onBuffer: @escaping AudioBufferHandler
    ) throws {
        let input = engine.inputNode
        // Il motore viene riusato tra una Riunione e l'altra: l'impostazione va applicata ogni volta.
        try input.setVoiceProcessingEnabled(echoCancellation)
        if echoCancellation {
            // Riduce al minimo l'abbassamento del volume delle altre app, call compresa.
            input.voiceProcessingOtherAudioDuckingConfiguration = .init(
                enableAdvancedDucking: false, duckingLevel: .min
            )
        }
        // Non toccare `mainMixerNode`: collegare il ramo d'uscita fa fallire
        // l'avvio con il voice processing attivo (errore -10875).
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.tapBlock(onBuffer))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw CaptureError.microphone(format: format.description, underlying: error)
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Costruito fuori dal main actor: il tap viene chiamato da un thread audio.
    private nonisolated static func tapBlock(
        _ onBuffer: @escaping AudioBufferHandler
    ) -> AVAudioNodeTapBlock {
        { buffer, time in
            onBuffer(buffer, time.isHostTimeValid ? time.hostTime : mach_absolute_time())
        }
    }
}
