import AVFoundation
import CoreAudio

/// Cattura la Traccia Altri: tutto l'audio di sistema, tramite un Core Audio process tap.
/// Steno non riproduce audio, quindi non serve escluderlo dal tap.
///
/// La prima volta macOS chiede il permesso "Registrazione solo audio di sistema".
@MainActor
final class SystemAudioCapture {
    private let queue = DispatchQueue(label: "dev.mameli.steno.system-audio", qos: .userInitiated)
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
        // Aspetta che gli ultimi buffer in coda siano stati scritti.
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
        tapDescription.name = "Steno"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted
        try checkCoreAudio(AudioHardwareCreateProcessTap(tapDescription, &tapID), "creazione del tap audio")

        var streamDescription = try readTapFormat()
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw CaptureError.unsupportedFormat("tap audio di sistema")
        }

        // Solo il tap, senza gli altoparlanti come dispositivo principale: con
        // il voice processing del microfono attivo, un aggregato che include
        // il dispositivo di uscita non riceve più audio.
        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Steno",
            kAudioAggregateDeviceUIDKey: "dev.mameli.steno.aggregate.\(UUID().uuidString)",
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
            "creazione del dispositivo aggregato"
        )
        try checkCoreAudio(
            AudioDeviceCreateIOProcIDWithBlock(
                &ioProcID, aggregateDeviceID, queue, Self.ioBlock(format: format, onBuffer: onBuffer)
            ),
            "registrazione della callback audio"
        )
        try checkCoreAudio(AudioDeviceStart(aggregateDeviceID, ioProcID), "avvio della cattura di sistema")
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
            "lettura del formato del tap"
        )
        return description
    }

    /// Costruito fuori dal main actor: la callback gira sulla coda audio.
    private nonisolated static func ioBlock(
        format: AVAudioFormat,
        onBuffer: @escaping AudioBufferHandler
    ) -> AudioDeviceIOBlock {
        { _, inputData, inputTime, _, _ in
            // Il buffer punta alla memoria di Core Audio: va usato solo dentro la callback.
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil) else {
                return
            }
            let time = inputTime.pointee
            let hostTimeValid = time.mFlags.contains(.hostTimeValid)
            onBuffer(buffer, hostTimeValid ? time.mHostTime : mach_absolute_time())
        }
    }
}
