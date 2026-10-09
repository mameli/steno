import Foundation

/// Takku's version numbers (`0.1.5`), as in `MARKETING_VERSION` and the release tags (`v0.1.5`).
public enum AppVersion {
    /// The version of a release tag: `v0.1.6` → `0.1.6`; `nil` if it is not a version.
    public static func fromTag(_ tag: String) -> String? {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return numbers(version) == nil ? nil : version
    }

    /// Whether `latest` comes after `current`, number by number (`0.1.10` after `0.1.9`).
    public static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let latest = numbers(latest), let current = numbers(current) else { return false }
        for index in 0..<max(latest.count, current.count) {
            let a = index < latest.count ? latest[index] : 0
            let b = index < current.count ? current[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func numbers(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }
}
