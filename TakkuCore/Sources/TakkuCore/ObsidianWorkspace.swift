import Foundation

/// What Obsidian saves in `.obsidian/workspace.json`: Takku only reads which note is on screen.
public enum ObsidianWorkspace {
    /// Path relative to the Vault of the note in the active tab, `nil` if the active panel is
    /// not a note (e.g. the file explorer) or the file cannot be read.
    public static func activeFile(in data: Data) -> String? {
        guard let workspace = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let activeID = workspace["active"] as? String
        else { return nil }
        // Tabs live in the main area, in the sidebars and in separate windows ("floating").
        for area in ["main", "left", "right", "floating"] {
            if let leaf = leaf(activeID, in: workspace[area]) {
                let view = leaf["state"] as? [String: Any]
                return (view?["state"] as? [String: Any])?["file"] as? String
            }
        }
        return nil
    }

    private static func leaf(_ id: String, in node: Any?) -> [String: Any]? {
        guard let node = node as? [String: Any] else { return nil }
        if node["type"] as? String == "leaf" {
            return node["id"] as? String == id ? node : nil
        }
        for child in node["children"] as? [Any] ?? [] {
            if let found = leaf(id, in: child) { return found }
        }
        return nil
    }
}
