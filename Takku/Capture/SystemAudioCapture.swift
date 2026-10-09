import AVFoundation
import CoreAudio

/// Captures the Others Track: all system audio, through a Core Audio process tap.
/// Takku plays no audio, so there is no need to exclude it from the tap.
///
/// The first time, macOS asks for the "System Audio Recording Only" permission.
@MainActor
final class SystemAudioCapture {
    private let queue = DispatchQueue(label: "app.takku.takku.system-audio", qos: .userInitiated)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    func start(onBuffer: @escaping AudioBufferHandler) throws {
        do {
            try startTapAndDevice(onBuffer: onBuffer)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        ioProcID = nil
        // Wait until the last queued buffers have been written.
        queue.sync {}
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func startTapAndDevice(onBuffer: @escaping AudioBufferHandler) throws {
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.name = "Takku"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted
        try checkCoreAudio(AudioHardwareCreateProcessTap(tapDescription, &tapID), "create the audio tap")

        var streamDescription = try readTapFormat()
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw CaptureError.unsupportedFormat("system audio tap")
        }

        // The tap only, without the speakers as main device: with voice processing
        // active on the microphone, an aggregate that includes the output device
        // stops receiving audio.
        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Takku",
            kAudioAggregateDeviceUIDKey: "app.takku.takku.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
            ]],
        ]
        try checkCoreAudio(
            AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregateDeviceID),
            "create the aggregate device"
        )
        try checkCoreAudio(
            AudioDeviceCreateIOProcIDWithBlock(
                &ioProcID, aggregateDeviceID, queue, Self.ioBlock(format: format, onBuffer: onBuffer)
            ),
            "register the audio callback"
        )
        try checkCoreAudio(AudioDeviceStart(aggregateDeviceID, ioProcID), "start the system capture")
    }

    private func readTapFormat() throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try checkCoreAudio(
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &description),
            "read the tap format"
        )
        return description
    }

    /// Built outside the main actor: the callback runs on the audio queue.
    private nonisolated static func ioBlock(
        format: AVAudioFormat,
        onBuffer: @escaping AudioBufferHandler
    ) -> AudioDeviceIOBlock {
        { _, inputData, inputTime, _, _ in
            // The buffer points to Core Audio's memory: use it only inside the callback.
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil) else {
                return
            }
            let time = inputTime.pointee
            let hostTimeValid = time.mFlags.contains(.hostTimeValid)
            onBuffer(buffer, hostTimeValid ? time.mHostTime : mach_absolute_time())
        }
    }
}
