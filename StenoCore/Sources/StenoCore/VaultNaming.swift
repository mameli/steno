import Foundation

/// Nomi dei file che Steno scrive nel Vault (senza estensione `.md`).
public enum VaultNaming {
    public static let defaultTitle = "Riunione"

    /// Caratteri che Obsidian non accetta nei nomi dei file o che rompono i link `[[…]]`.
    private static let forbidden = CharacterSet(charactersIn: "*\"\\/<>:|?#^[]")

    public static func noteName(startedAt: Date, title: String, timeZone: TimeZone = .current) -> String {
        "\(DateFormatter.posix("yyyy-MM-dd HHmm", timeZone: timeZone).string(from: startedAt)) - \(sanitized(title))"
    }

    /// `name` se è libero, altrimenti `name (2)`, `name (3)`… Il confronto ignora maiuscole
    /// e minuscole, come il file system del Mac.
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
        let words = title
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? defaultTitle : words.joined(separator: " ")
    }
}
