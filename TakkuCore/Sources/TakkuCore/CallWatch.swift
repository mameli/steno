import Foundation

/// Suggests starting a Meeting when another app keeps using the microphone (a call), and stopping
/// it when the call app lets it go. It never starts or stops anything itself. Fed every few
/// seconds with the apps using an audio input, Takku excluded; times in seconds.
public struct CallWatch: Sendable {
    public enum Suggestion: Equatable, Sendable {
        /// "Looks like a call in <app>": start recording?
        case start(app: String)
        /// "The call seems over": stop recording?
        case stop
    }

    /// Using the microphone this long without a break is a call, not a dictation.
    public static let startAfter: TimeInterval = 15
    /// No app on the microphone for this long while recording: the call is over.
    public static let stopAfter: TimeInterval = 30

    /// Since when each app has been using the microphone without a break.
    private var usingSince: [String: TimeInterval] = [:]
    /// Apps already suggested (or recorded) in their current stretch of use: once per stretch.
    private var handled: Set<String> = []
    /// When an app was last seen on the microphone during the Meeting in progress.
    private var lastCallSeen: TimeInterval?
    private var isStopSuggested = false

    public init() {}

    public mutating func update(appsUsingInput apps: Set<String>, isRecording: Bool, now: TimeInterval) -> Suggestion? {
        usingSince = usingSince.filter { apps.contains($0.key) }
        handled.formIntersection(apps)
        for app in apps where usingSince[app] == nil { usingSince[app] = now }

        guard isRecording else {
            lastCallSeen = nil
            isStopSuggested = false
            let call = usingSince
                .filter { !handled.contains($0.key) && now - $0.value >= Self.startAfter }
                .min { $0.value < $1.value }?.key
            guard let call else { return nil }
            handled.insert(call)
            return .start(app: call)
        }

        // A call going on while recording needs no suggestion, not even after the stop.
        handled.formUnion(apps)
        if !apps.isEmpty {
            lastCallSeen = now
            isStopSuggested = false
            return nil
        }
        guard let lastCallSeen, !isStopSuggested, now - lastCallSeen >= Self.stopAfter else { return nil }
        isStopSuggested = true
        return .stop
    }
}
