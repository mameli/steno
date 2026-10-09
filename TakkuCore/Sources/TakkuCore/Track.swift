/// One of the two audio sources of a Recording.
public enum Track: String, Codable, Sendable, CaseIterable {
    /// The microphone.
    case me
    /// System audio.
    case others

    /// How the Track appears in the Transcript; Others only where the Speakers are not told apart.
    public var label: String {
        switch self {
        case .me: "Me"
        case .others: "Others"
        }
    }
}
