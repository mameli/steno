import Foundation

/// The lines of a Markdown file, normalised (no BOM, `\n` line endings), with the
/// position of its YAML frontmatter.
struct MarkdownLines {
    var lines: [String]

    init(_ content: String) {
        var normalized = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }
        lines = normalized.components(separatedBy: "\n")
    }

    var text: String { lines.joined(separator: "\n") }

    /// Index of the line that closes the frontmatter, `nil` if the file has none.
    var frontmatterClose: Int? {
        guard let first = lines.first, Self.isLine(first, "---") else { return nil }
        return lines.indices.dropFirst().first { Self.isLine(lines[$0], "---") }
    }

    /// Index of the first line after the frontmatter (0 without frontmatter).
    var bodyStart: Int {
        frontmatterClose.map { $0 + 1 } ?? 0
    }

    /// Value of a top-level `key: value` line of the frontmatter.
    func value(_ key: String) -> String? {
        guard let close = frontmatterClose,
              let line = lines[1..<close].first(where: { $0.hasPrefix("\(key):") })
        else { return nil }
        return line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    /// Items of a top-level list of the frontmatter, written as a block (`- item` lines under the key)
    /// or inline (`[a, b]`); a single value counts as one item. `nil` if the key is missing.
    func list(_ key: String) -> [String]? {
        guard let close = frontmatterClose,
              let line = lines[1..<close].firstIndex(where: { $0.hasPrefix("\(key):") })
        else { return nil }
        let inline = lines[line].dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        if inline.hasPrefix("["), inline.hasSuffix("]") {
            return inline.dropFirst().dropLast().split(separator: ",").map { Self.unquoted(String($0)) }.filter { !$0.isEmpty }
        }
        if !inline.isEmpty { return [Self.unquoted(inline)] }
        var items: [String] = []
        for item in lines[(line + 1)..<close] {
            let trimmed = item.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-") else { break }
            let value = Self.unquoted(String(trimmed.dropFirst()))
            if !value.isEmpty { items.append(value) }
        }
        return items
    }

    private static func unquoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        for quote in ["\"", "'"] where trimmed.count >= 2 && trimmed.hasPrefix(quote) && trimmed.hasSuffix(quote) {
            return String(trimmed.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
        }
        return trimmed
    }

    static func isLine(_ line: String, _ text: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == text
    }
}
