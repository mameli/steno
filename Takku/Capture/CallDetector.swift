import AppKit
import CoreAudio
import TakkuCore

/// Every 3 seconds reads which apps are using an audio input (Core Audio process objects: nothing
/// is recorded or listened to) and passes them to `CallWatch`, which decides when to suggest
/// starting or stopping a Meeting. Takku itself is ignored.
@MainActor
final class CallDetector {
    private var watch = CallWatch()
    private var poller: Task<Void, Never>?

    /// `isRecording` is read at every poll; `suggest` is called with what `CallWatch` suggests.
    func start(isRecording: @escaping @MainActor () -> Bool, suggest: @escaping @MainActor (CallWatch.Suggestion) -> Void) {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if AppSettings.suggestCalls {
                    let apps = Self.appsUsingInput()
                    let now = ProcessInfo.processInfo.systemUptime
                    if let suggestion = self.watch.update(appsUsingInput: apps, isRecording: isRecording(), now: now) {
                        suggest(suggestion)
                    }
                } else {
                    self.watch = CallWatch()
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Listening for "Hey Siri" is not a call.
    private static let ignoredProcesses: Set<String> = ["com.apple.CoreSpeech"]

    /// System processes that capture for an app without being part of it.
    private static let knownProcesses = [
        "com.apple.avconferenced": "FaceTime",
        "com.apple.WebKit.GPU": "Safari",
    ]

    /// The names of the apps with a process using an audio input, Takku excluded.
    private static func appsUsingInput() -> Set<String> {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var apps: Set<String> = []
        for process in processObjects() where isRunningInput(process) {
            guard let pid = processPID(process), pid != ownPID else { continue }
            let bundleID = bundleID(process)
            if let bundleID, ignoredProcesses.contains(bundleID) { continue }
            apps.insert(appName(pid: pid, bundleID: bundleID))
        }
        return apps
    }

    /// The app a process belongs to: a helper (`com.google.Chrome.helper`) is named after the app
    /// whose bundle identifier starts its own.
    private static func appName(pid: pid_t, bundleID: String?) -> String {
        if let bundleID, let known = knownProcesses[bundleID] { return known }
        if var components = bundleID?.split(separator: ".").map(String.init) {
            while components.count >= 2 {
                let candidate = components.joined(separator: ".")
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: candidate)
                    .first(where: { $0.activationPolicy == .regular }),
                   let name = app.localizedName {
                    return name
                }
                components.removeLast()
            }
        }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
            ?? bundleID
            ?? String(localized: "another app")
    }

    // MARK: - Core Audio

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0
        else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr
        else { return [] }
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func isRunningInput(_ process: AudioObjectID) -> Bool {
        var running: UInt32 = 0
        return read(kAudioProcessPropertyIsRunningInput, of: process, into: &running) && running != 0
    }

    private static func processPID(_ process: AudioObjectID) -> pid_t? {
        var pid: pid_t = 0
        return read(kAudioProcessPropertyPID, of: process, into: &pid) ? pid : nil
    }

    private static func bundleID(_ process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() as String?, !string.isEmpty
        else { return nil }
        return string
    }

    private static func read<Value>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID, into value: inout Value) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Value>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }
}
