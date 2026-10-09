import Foundation

/// Whether a Track is recording anything, from when it last received sound. Times in seconds
/// from the start of the Meeting.
public enum TrackSilence {
    /// Peak below -80 dBFS: digital silence. A real microphone's noise floor is higher, so a
    /// Track that stays below this is not receiving audio at all.
    public static let soundThreshold: Float = 0.0001
    /// Silence shorter than this is a pause in the conversation.
    public static let warningAfter: TimeInterval = 120

    /// Whole minutes without sound to show in the menu, `nil` while the silence is shorter than
    /// `warningAfter`. `lastSound` is `nil` if the Track has had no sound since the start.
    public static func silentMinutes(lastSound: TimeInterval?, now: TimeInterval) -> Int? {
        let silence = now - (lastSound ?? 0)
        guard silence >= warningAfter else { return nil }
        return Int(silence / 60)
    }

    /// No sound since the start for `warningAfter`: the Meeting would be lost without a warning.
    public static func neverHeard(lastSound: TimeInterval?, now: TimeInterval) -> Bool {
        lastSound == nil && now >= warningAfter
    }
}
