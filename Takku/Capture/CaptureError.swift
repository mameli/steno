import Foundation

enum CaptureError: LocalizedError {
    case coreAudio(step: String, status: OSStatus)
    case unsupportedFormat(String)
    case microphone(format: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .coreAudio(let step, let status):
            String(localized: "Core Audio could not complete \"\(step)\" (code \(status)).")
        case .unsupportedFormat(let format):
            String(localized: "Unsupported audio format: \(format).")
        case .microphone(let format, let underlying):
            String(localized: "The microphone does not start (\(format)): \(underlying.localizedDescription)")
        }
    }
}

func checkCoreAudio(_ status: OSStatus, _ step: String) throws {
    guard status == noErr else { throw CaptureError.coreAudio(step: step, status: status) }
}
