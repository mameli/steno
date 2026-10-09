import Testing
import StenoCore

@Suite("Meeting languages")
struct MeetingLanguagesTests {
    @Test("languages are kept in the Settings order, once, and only if offered")
    func normalized() {
        #expect(MeetingLanguages.normalized(["fr", "en", "fr", "xx", "it"]) == ["it", "en", "fr"])
        #expect(MeetingLanguages.normalized(["de", "es"]) == ["de", "es"])
    }

    @Test("with nothing valid ticked, Italian and English as in v1")
    func emptyFallsBackToDefaults() {
        #expect(MeetingLanguages.normalized([]) == ["it", "en"])
        #expect(MeetingLanguages.normalized(["xx"]) == ["it", "en"])
    }

    @Test("a single language ticked is forced; several are detected")
    func forced() {
        #expect(MeetingLanguages.forced(["fr"]) == "fr")
        #expect(MeetingLanguages.forced(["it", "en"]) == nil)
        #expect(MeetingLanguages.forced([]) == nil)
    }

    @Test("when nothing is detected the first ticked language is used, Italian first")
    func fallback() {
        #expect(MeetingLanguages.fallback(["en", "it"]) == "it")
        #expect(MeetingLanguages.fallback(["fr", "en"]) == "en")
        #expect(MeetingLanguages.fallback(["fr", "de"]) == "fr")
    }

    @Test("the v1 language setting becomes the ticked languages")
    func migrated() {
        #expect(MeetingLanguages.migrated(fromLanguageSetting: "it") == ["it"])
        #expect(MeetingLanguages.migrated(fromLanguageSetting: "en") == ["en"])
        #expect(MeetingLanguages.migrated(fromLanguageSetting: "auto") == ["it", "en"])
        #expect(MeetingLanguages.migrated(fromLanguageSetting: nil) == ["it", "en"])
    }
}
