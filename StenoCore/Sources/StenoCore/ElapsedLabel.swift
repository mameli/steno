import Foundation

/// Etichetta del timer mostrata nella barra dei menu durante la registrazione.
public func elapsedLabel(_ elapsed: TimeInterval) -> String {
    let total = Int(elapsed)
    let hours = total / 3600
    let minutes = total % 3600 / 60
    let seconds = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}
