/// One of the two audio sources of a Recording.
public enum Track: String, Codable, Sendable, CaseIterable {
    /// The microphone.
    case me
    /// System audio.
    case others

    /// How the Track appears in the Transcript.
    public var label: String {
        switch self {
        case .me: "Me"
        case .others: "Others"
        }
    }

    /// Segment lists saved before the English rewrite used "io" and "altri".
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "me", "io": self = .me
        case "others", "altri": self = .others
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown track \(value)"))
        }
    }
}
