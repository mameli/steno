import AVFoundation
import os

private let logger = Logger(subsystem: "dev.mameli.steno", category: "capture")

/// Captures the Me Track from the default microphone. The engine stops whenever the audio
/// configuration changes: voice processing itself switches Bluetooth headsets (AirPods) to call
/// mode right after the start, and the default microphone can change during a Meeting. The same
/// engine is started again first (a new one would switch the headset back and forth forever);
/// if no audio arrives from it, the microphone really changed and a new engine takes the new one.
/// The writer fills the hole with silence, so the Track stays aligned.
@MainActor
final class MicrophoneCapture {
    /// Restarts within a minute after which Steno gives up: a device that keeps changing
    /// must not turn into a loop.
    private static let maxRestartsPerMinute = 5
    /// Without a buffer for this long after a restart, the engine is not hearing anything.
    private static let silentAfterRestart: Duration = .seconds(2)

    private var engine = AVAudioEngine()
    /// Where buffers go while a Meeting is recorded; `nil` when stopped.
    private var onBuffer: AudioBufferHandler?
    private var configurationObserver: NSObjectProtocol?
    private var restarts: [Date] = []
    private let lastBuffer = LastBufferTime()

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
        installTap(on: input, onBuffer: onBuffer)
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

    private func installTap(on input: AVAudioInputNode, onBuffer: @escaping AudioBufferHandler) {
        input.installTap(
            onBus: 0, bufferSize: 4096, format: input.outputFormat(forBus: 0),
            block: Self.tapBlock(onBuffer, lastBuffer: lastBuffer)
        )
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
        guard let onBuffer, !engine.isRunning else { return }
        restarts = restarts.filter { $0.timeIntervalSinceNow > -60 }
        guard restarts.count < Self.maxRestartsPerMinute else {
            logger.error("Microphone changing too often: the Me Track stays silent until the stop")
            return
        }
        restarts.append(Date())
        // The same engine first, with the format the microphone has now.
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        installTap(on: input, onBuffer: onBuffer)
        engine.prepare()
        do {
            try engine.start()
            logger.info("Microphone resumed after a configuration change")
        } catch {
            logger.error("Microphone resume failed: \(error, privacy: .public)")
        }
        let resumedAt = Date()
        Task {
            try? await Task.sleep(for: Self.silentAfterRestart)
            replaceEngineIfSilent(since: resumedAt)
        }
    }

    /// The engine did not get audio back: the default microphone changed, take it with a new engine.
    private func replaceEngineIfSilent(since resumedAt: Date) {
        guard onBuffer != nil, lastBuffer.date < resumedAt else { return }
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
        _ onBuffer: @escaping AudioBufferHandler, lastBuffer: LastBufferTime
    ) -> AVAudioNodeTapBlock {
        { buffer, time in
            lastBuffer.date = Date()
            onBuffer(buffer, time.isHostTimeValid ? time.hostTime : mach_absolute_time())
        }
    }
}

/// When the microphone last delivered audio: written on the audio thread, read on the main one.
private final class LastBufferTime: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date.distantPast

    var date: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
