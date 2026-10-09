import Testing
import StenoCore

@Suite("Update check")
struct AppVersionTests {
    @Test("a release tag gives its version; other tags give none")
    func fromTag() {
        #expect(AppVersion.fromTag("v0.1.6") == "0.1.6")
        #expect(AppVersion.fromTag("0.2") == "0.2")
        #expect(AppVersion.fromTag("v0.2-beta") == nil)
        #expect(AppVersion.fromTag("latest") == nil)
    }

    @Test("versions compare number by number")
    func isNewer() {
        #expect(AppVersion.isNewer("0.1.6", than: "0.1.5"))
        #expect(AppVersion.isNewer("0.1.10", than: "0.1.9"))
        #expect(AppVersion.isNewer("0.2", than: "0.1.9"))
        #expect(AppVersion.isNewer("1.0.0", than: "0.9"))
        #expect(!AppVersion.isNewer("0.1.5", than: "0.1.5"))
        #expect(!AppVersion.isNewer("0.1", than: "0.1.0"))
        #expect(!AppVersion.isNewer("0.1.4", than: "0.1.5"))
        #expect(!AppVersion.isNewer("garbage", than: "0.1.5"))
    }
}
