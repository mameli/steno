import Foundation

/// A file in the Vault that defines the structure and instructions of the Summary for a kind of Meeting.
public struct Template: Equatable, Sendable {
    public let name: String
    /// Language code that forces the Summary language (`it`, `en`, `fr`…), `nil` to use the Meeting's.
    public let summaryLanguage: String?
    /// Free-form instructions and structure, passed to the model as they are.
    public let body: String

    /// The Template Steno creates in the Vault when the Templates folder is empty: notes by
    /// topic, in Meeting order, and Next steps at the end (like Granola).
    public static let defaultName = "Notes"
    public static let defaultFileContent = """
        ---
        name: Notes
        summary_language: auto
        ---
        Write the meeting notes the way an attentive colleague would take them, not as formal minutes.

        - Split the meeting into topics, in the order they were discussed. For each topic \
        a `###` heading with a short, concrete title.
        - Under each topic a bullet list: one bullet per idea, proposal, decision or problem, \
        with sub-bullets for reasons, details, people, figures, dates and links. Short sentences, no preambles.
        - Decisions go in the topic they belong to, not in a separate section.
        - No opening summary and no generic conclusions.

        ### Next steps
        One bullet per agreed action, in the form `- [ ] What to do (Who)`, with a sub-bullet \
        for context and deadline when there are any.

        """

    /// The content of a new Template created by the user: the default one with the chosen name.
    public static func newFileContent(name: String) -> String {
        defaultFileContent.replacingOccurrences(of: "name: \(defaultName)", with: "name: \(name)")
    }

    public init(fileName: String, content: String) {
        let markdown = MarkdownLines(content)
        name = markdown.value("name").flatMap { $0.isEmpty ? nil : $0 } ?? fileName
        summaryLanguage = markdown.value("summary_language").flatMap(Language.code)
        body = markdown.lines[markdown.bodyStart...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
