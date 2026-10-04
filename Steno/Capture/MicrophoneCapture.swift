import AVFoundation

/// Captures the Me Track from the default microphone.
@MainActor
final class MicrophoneCapture {
    private let engine = AVAudioEngine()

    func start(
        echoCancellation: Bool,
        onBuffer: @escaping AudioBufferHandler
    ) throws {
        let input = engine.inputNode
        // The engine is reused across Meetings: the setting must be applied every time.
        try input.setVoiceProcessingEnabled(echoCancellation)
        if echoCancellation {
            // Keeps to a minimum the volume ducking of other apps, the call included.
            input.voiceProcessingOtherAudioDuckingConfiguration = .init(
                enableAdvancedDucking: false, duckingLevel: .min
            )
        }
        // Do not touch `mainMixerNode`: connecting the output branch makes the start
        // fail with voice processing active (error -10875).
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

    /// Built outside the main actor: the tap is called from an audio thread.
    private nonisolated static func tapBlock(
        _ onBuffer: @escaping AudioBufferHandler
    ) -> AVAudioNodeTapBlock {
        { buffer, time in
            onBuffer(buffer, time.isHostTimeValid ? time.hostTime : mach_absolute_time())
        }
    }
}
