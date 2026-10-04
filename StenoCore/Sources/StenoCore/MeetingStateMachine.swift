import Foundation

public enum MeetingState: Equatable, Sendable {
    case idle
    case inProgress(startedAt: Date)
}

public enum MeetingStateError: Error, Equatable, Sendable {
    case alreadyInProgress
    case notInProgress
}

public struct MeetingStateMachine: Sendable {
    public private(set) var state: MeetingState = .idle

    public init() {}

    public mutating func start(at date: Date) throws {
        guard state == .idle else { throw MeetingStateError.alreadyInProgress }
        state = .inProgress(startedAt: date)
    }

    public mutating func stop(at date: Date) throws -> DateInterval {
        guard case .inProgress(let startedAt) = state else {
            throw MeetingStateError.notInProgress
        }
        state = .idle
        return DateInterval(start: startedAt, end: date)
    }
}
