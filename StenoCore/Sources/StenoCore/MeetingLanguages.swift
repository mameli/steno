import Foundation

/// The languages a Meeting can be in, ticked in Settings. Detection picks only among them; with
/// one ticked it is forced and there is no detection.
public enum MeetingLanguages {
    /// The languages both engines handle (those of Parakeet v3), in the order of the Settings list:
    /// Italian and English first, then by English name. The first one ticked is the fallback when
    /// nothing can be detected.
    public static let offered = ["it", "en"] + [
        "bg", "hr", "cs", "da", "nl", "et", "fi", "fr", "de", "el", "hu", "lv", "lt", "mt", "pl", "pt", "ro",
        "ru", "sk", "sl", "es", "sv", "uk",
    ]

    /// What v1 did: Italian or English.
    public static let defaults = ["it", "en"]

    /// Only offered languages, once each, in the Settings order; the defaults if none is left.
    public static func normalized(_ codes: [String]) -> [String] {
        let ticked = offered.filter(codes.contains)
        return ticked.isEmpty ? defaults : ticked
    }

    /// The language to force, when only one is ticked.
    public static func forced(_ codes: [String]) -> String? {
        let ticked = normalized(codes)
        return ticked.count == 1 ? ticked[0] : nil
    }

    /// The language used when detection says nothing.
    public static func fallback(_ codes: [String]) -> String {
        normalized(codes)[0]
    }

    /// The languages from v1's `language` setting: `it` or `en` forced, otherwise (`auto`) both.
    public static func migrated(fromLanguageSetting value: String?) -> [String] {
        guard let value, defaults.contains(value) else { return defaults }
        return [value]
    }
}
