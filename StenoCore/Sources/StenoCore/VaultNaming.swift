import Foundation

/// Nomi dei file che Steno scrive nel Vault (senza estensione `.md`).
public enum VaultNaming {
    public static let defaultTitle = "Riunione"

    /// Caratteri che Obsidian non accetta nei nomi dei file o che rompono i link `[[…]]`.
    private static let forbidden = CharacterSet(charactersIn: "*\"\\/<>:|?#^[]")

    public static func noteName(startedAt: Date, title: String, timeZone: TimeZone = .current) -> String {
        "\(DateFormatter.posix("yyyy-MM-dd HHmm", timeZone: timeZone).string(from: startedAt)) - \(sanitized(title))"
    }

    /// Il nuovo nome della Nota della Riunione con il titolo generato, oppure `nil` se l'utente
    /// l'ha già rinominata (non ha più il nome provvisorio, eventualmente con suffisso " (n)").
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
        fileName(title) ?? defaultTitle
    }

    /// Un nome scelto dall'utente reso valido come nome di file in Obsidian, `nil` se non resta niente.
    public static func fileName(_ name: String) -> String? {
        let words = name
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}
