import Foundation

enum CaptureError: LocalizedError {
    case coreAudio(step: String, status: OSStatus)
    case unsupportedFormat(String)
    case microphone(format: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .coreAudio(let step, let status):
            "Core Audio non riesce a completare \"\(step)\" (codice \(status))."
        case .unsupportedFormat(let format):
            "Formato audio non supportato: \(format)."
        case .microphone(let format, let underlying):
            "Il microfono non parte (\(format)): \(underlying.localizedDescription)"
        }
    }
}

func checkCoreAudio(_ status: OSStatus, _ step: String) throws {
    guard status == noErr else { throw CaptureError.coreAudio(step: step, status: status) }
}
