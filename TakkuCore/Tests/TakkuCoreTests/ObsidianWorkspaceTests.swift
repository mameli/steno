import Foundation
import Testing
import TakkuCore

@Suite("Reading which note Obsidian shows")
struct ObsidianWorkspaceTests {
    /// Shape of `.obsidian/workspace.json`, trimmed to what matters.
    func workspace(active: String, floating: String = "") -> Data {
        Data("""
            {
              "main": {
                "id": "root", "type": "split",
                "children": [{
                  "id": "tabs", "type": "tabs",
                  "children": [
                    {"id": "a", "type": "leaf", "state": {"type": "markdown", "state": {"file": "Meetings/2026-10-05 1140 - Meeting.md"}}},
                    {"id": "b", "type": "leaf", "state": {"type": "markdown", "state": {"file": "Projects/Plan.md"}}}
                  ]
                }]
              },
              "left": {"id": "left", "type": "split", "children": [
                {"id": "files", "type": "leaf", "state": {"type": "file-explorer", "state": {}}}
              ]},
              \(floating)
              "active": "\(active)"
            }
            """.utf8)
    }

    @Test("the active tab's note is the one on screen")
    func activeNote() {
        #expect(ObsidianWorkspace.activeFile(in: workspace(active: "a")) == "Meetings/2026-10-05 1140 - Meeting.md")
        #expect(ObsidianWorkspace.activeFile(in: workspace(active: "b")) == "Projects/Plan.md")
    }

    @Test("a note in a separate Obsidian window is found too")
    func floatingWindow() {
        let floating = """
            "floating": {"id": "f", "type": "floating", "children": [{"id": "w", "type": "window", "children": [
              {"id": "c", "type": "leaf", "state": {"type": "markdown", "state": {"file": "Meetings/Other.md"}}}
            ]}]},
            """
        #expect(ObsidianWorkspace.activeFile(in: workspace(active: "c", floating: floating)) == "Meetings/Other.md")
    }

    @Test("no note when the active panel is not a note, or the file is unreadable")
    func noNote() {
        #expect(ObsidianWorkspace.activeFile(in: workspace(active: "files")) == nil)
        #expect(ObsidianWorkspace.activeFile(in: workspace(active: "missing")) == nil)
        #expect(ObsidianWorkspace.activeFile(in: Data("not json".utf8)) == nil)
    }
}
