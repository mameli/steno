import AVFoundation
import os

private let logger = Logger(subsystem: "dev.mameli.steno", category: "capture")

/// Captures the Me Track from the default microphone. When the default microphone changes
/// during a Meeting (AirPods connected or removed) the engine stops: it is started again on
/// the new one. The writer fills the hole with silence, so the Track stays aligned.
@MainActor
final class MicrophoneCapture {
    /// Restarts within a minute after which Steno gives up: a device that keeps changing
    /// must not turn into a loop.
    private static let maxRestartsPerMinute = 5

    private var engine = AVAudioEngine()
    /// Where buffers go while a Meeting is recorded; `nil` when stopped.
    private var onBuffer: AudioBufferHandler?
    private var configurationObserver: NSObjectProtocol?
    private var restarts: [Date] = []

    func start(onBuffer: @escaping AudioBufferHandler) throws {
        self.onBuffer = onBuffer
        restarts = []
        try startEngine()
    }

    func stop() {
        onBuffer = nil
        stopEngine()
    }

    /// A new engine every time: it takes the current default microphone and its format.
    private func startEngine() throws {
        guard let onBuffer else { return }
        engine = AVAudioEngine()
        let input = engine.inputNode
        // Echo cancellation: without it the microphone also records the others from the speakers.
        try input.setVoiceProcessingEnabled(true)
        // Keeps to a minimum the volume ducking of other apps, the call included.
        input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        // Do not touch `mainMixerNode`: connecting the output branch makes the start
        // fail with voice processing active (error -10875).
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.tapBlock(onBuffer))
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.devicesChanged() }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw CaptureError.microphone(format: format.description, underlying: error)
        }
    }

    private func stopEngine() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Several notifications can arrive for one change, and starting voice processing can post
    /// one too: after a short wait the engine is started again only if it is really stopped.
    private func devicesChanged() {
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            restartIfStopped()
        }
    }

    private func restartIfStopped() {
        guard onBuffer != nil, !engine.isRunning else { return }
        restarts = restarts.filter { $0.timeIntervalSinceNow > -60 }
        guard restarts.count < Self.maxRestartsPerMinute else {
            logger.error("Microphone changing too often: the Me Track stays silent until the stop")
            return
        }
        restarts.append(Date())
        stopEngine()
        do {
            try startEngine()
            logger.info("Microphone restarted on the new default device")
        } catch {
            logger.error("Microphone restart failed, trying again: \(error, privacy: .public)")
            devicesChanged()
        }
    }

    #if DEBUG
    /// Tests: the microphone goes silent for 2 seconds as if the device had changed.
    func simulateDeviceChange() {
        engine.stop()
        Task {
            try? await Task.sleep(for: .seconds(2))
            devicesChanged()
        }
    }
    #endif

    /// Built outside the main actor: the tap is called from an audio thread.
    private nonisolated static func tapBlock(
        _ onBuffer: @escaping AudioBufferHandler
    ) -> AVAudioNodeTapBlock {
        { buffer, time in
            onBuffer(buffer, time.isHostTimeValid ? time.hostTime : mach_absolute_time())
        }
    }
}
