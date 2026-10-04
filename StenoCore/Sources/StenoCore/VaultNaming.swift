import Foundation

/// Names of the files Steno writes in the Vault (without the `.md` extension).
public enum VaultNaming {
    public static let defaultTitle = "Meeting"

    /// Characters Obsidian does not accept in file names or that break `[[…]]` links.
    private static let forbidden = CharacterSet(charactersIn: "*\"\\/<>:|?#^[]")

    public static func noteName(startedAt: Date, title: String, timeZone: TimeZone = .current) -> String {
        "\(DateFormatter.posix("yyyy-MM-dd HHmm", timeZone: timeZone).string(from: startedAt)) - \(sanitized(title))"
    }

    /// The new name of the Meeting note with the generated title, or `nil` if the user already
    /// renamed it (it no longer has the provisional name, possibly with a " (n)" suffix).
    public static func renamedNoteName(current: String, startedAt: Date, title: String, timeZone: TimeZone = .current) -> String? {
        let provisional = noteName(startedAt: startedAt, title: defaultTitle, timeZone: timeZone)
        guard current == provisional || isSuffixed(current, of: provisional) else { return nil }
        return noteName(startedAt: startedAt, title: title, timeZone: timeZone)
    }

    private static func isSuffixed(_ name: String, of base: String) -> Bool {
        guard name.hasPrefix(base + " ("), name.hasSuffix(")") else { return false }
        let number = name.dropFirst(base.count + 2).dropLast()
        return !number.isEmpty && number.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// `name` if it is free, otherwise `name (2)`, `name (3)`… The comparison ignores case,
    /// like the Mac file system.
    public static func available(_ name: String, taken: Set<String>) -> String {
        let taken = Set(taken.map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        var suffix = 2
        while taken.contains("\(name) (\(suffix))".lowercased()) {
            suffix += 1
        }
        return "\(name) (\(suffix))"
    }

    private static func sanitized(_ title: String) -> String {
        fileName(title) ?? defaultTitle
    }

    /// A user-chosen name made valid as an Obsidian file name, `nil` if nothing is left.
    public static func fileName(_ name: String) -> String? {
        let words = name
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}
