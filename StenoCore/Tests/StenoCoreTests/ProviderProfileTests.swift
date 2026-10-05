import Foundation
import Testing
import StenoCore

@Suite("Checking a Profile's base URL")
struct ProviderProfileTests {
    func profile(_ baseURL: String) -> ProviderProfile {
        ProviderProfile(name: "Test", baseURL: baseURL, model: "m", maxContextTokens: 32_000)
    }

    @Test("https is accepted anywhere, plain http only for servers on this Mac", arguments: [
        "https://api.mistral.ai/v1", "http://localhost:8080/v1", "http://127.0.0.1:8080/v1", "http://[::1]:8080/v1",
        " https://api.regolo.ai/v1 ",
    ])
    func accepted(baseURL: String) throws {
        #expect(try profile(baseURL).validatedBaseURL().scheme != nil)
    }

    @Test("plain http to another machine is refused: key and Transcript would travel readable", arguments: [
        "http://api.mistral.ai/v1", "http://server.local:8080/v1", "http://192.168.1.20:8080/v1",
    ])
    func insecure(baseURL: String) {
        #expect(throws: ProviderProfile.URLError.insecure(baseURL)) { try profile(baseURL).validatedBaseURL() }
    }

    @Test("an address without scheme or host is refused", arguments: ["", "api.mistral.ai/v1", "ftp://x.eu/v1", "https://"])
    func invalid(baseURL: String) {
        #expect(throws: ProviderProfile.URLError.invalid(baseURL)) { try profile(baseURL).validatedBaseURL() }
    }
}
