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

    /// Value of a top-level `key: value` line of the frontmatter, trying the keys in order.
    func value(_ keys: String...) -> String? {
        guard let close = frontmatterClose else { return nil }
        for key in keys {
            if let line = lines[1..<close].first(where: { $0.hasPrefix("\(key):") }) {
                return line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    static func isLine(_ line: String, _ text: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == text
    }
}
