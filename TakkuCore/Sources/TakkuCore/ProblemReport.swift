import Foundation

/// What *Report a problem…* says about Takku and the Mac: filled in the GitHub bug form
/// (`.github/ISSUE_TEMPLATE/bug_report.yml`, fields by id) and written at the top of the report
/// file, above the logs. In English, like the issues. Nothing that names the user, the Meetings
/// or the provider's address.
public struct ProblemReport: Equatable, Sendable {
    public var version: String
    public var system: String
    /// One of the form's "Installed with" options, or `nil` to let the user choose.
    public var installedWith: String?
    public var transcriptionModel: String
    public var summary: String

    public init(version: String, system: String, installedWith: String?, transcriptionModel: String, summary: String) {
        self.version = version
        self.system = system
        self.installedWith = installedWith
        self.transcriptionModel = transcriptionModel
        self.summary = summary
    }

    /// The Summary Profile by model and where it runs: its name and base URL can name a company.
    public static func summary(of profile: ProviderProfile?) -> String {
        guard let profile else { return "Transcript only" }
        return "\(profile.model) (\(profile.runsOnThisMac ? "on this Mac" : "remote"))"
    }

    public var issueURL: URL {
        var components = URLComponents(string: "https://github.com/mameli/Takku/issues/new")!
        let fields: [(String, String?)] = [
            ("template", "bug_report.yml"), ("version", version), ("macos", system),
            ("install", installedWith), ("model", transcriptionModel), ("summary", summary),
        ]
        components.queryItems = fields.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
        return components.url!
    }

    public func text(logs: String) -> String {
        """
        Takku problem report
        Check this file before attaching it to a public issue, and remove anything you don't want to share.

        Takku: \(version)
        System: \(system)
        Installed with: \(installedWith ?? "unknown")
        Transcription model: \(transcriptionModel)
        Summary: \(summary)

        Logs:
        \(logs)

        """
    }
}
