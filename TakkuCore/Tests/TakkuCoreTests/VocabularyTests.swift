import Testing
import TakkuCore

@Suite("Vocabulary")
struct VocabularyTests {
    @Test("an entry gives the term, its variants and its description")
    func fullEntry() {
        let vocabulary = Vocabulary(fileContent: "- Takku = abtakku, takku | our app for recording meetings")

        #expect(vocabulary.entries == [
            Vocabulary.Entry(term: "Takku", variants: ["abtakku", "takku"], description: "our app for recording meetings"),
        ])
    }

    @Test("an entry can be just the term")
    func termOnly() {
        #expect(Vocabulary(fileContent: "- Mameli").entries == [Vocabulary.Entry(term: "Mameli")])
    }

    @Test("lines that are not list items are ignored, so the file can hold free text")
    func freeText() {
        let vocabulary = Vocabulary(fileContent: """
            # Vocabulary

            Names we say in meetings:

            - Scaleway = scale uai
            Not a list item = ignored
            - Mistral
            """)

        #expect(vocabulary.entries.map(\.term) == ["Scaleway", "Mistral"])
    }

    @Test("the same term twice: the first entry counts; the same variant under two terms: the first counts")
    func duplicates() {
        let vocabulary = Vocabulary(fileContent: """
            - Takku = abtakku
            - Mistral = mistrel, abtakku
            - takku = stenno
            """)

        #expect(vocabulary.entries == [
            Vocabulary.Entry(term: "Takku", variants: ["abtakku"]),
            Vocabulary.Entry(term: "Mistral", variants: ["mistrel"]),
        ])
    }

    @Test("a variant equal to its term is dropped, one that differs only in case is kept; empty pieces are dropped")
    func degenerateInput() {
        let vocabulary = Vocabulary(fileContent: """
            - WhisperKit = WhisperKit, whisperkit,, ,
            - = orphan variant
            -
            - Mameli |
            """)

        #expect(vocabulary.entries == [
            Vocabulary.Entry(term: "WhisperKit", variants: ["whisperkit"]),
            Vocabulary.Entry(term: "Mameli", description: nil),
        ])
    }

    @Test("the example file explains the syntax but does not add entries by itself")
    func exampleFile() {
        #expect(Vocabulary.exampleFileContent.contains("`- Scaleway = scale uai | our EU cloud provider`"))
        #expect(Vocabulary(fileContent: Vocabulary.exampleFileContent).entries.isEmpty)
    }

    @Test("a missing or empty file gives an empty Vocabulary")
    func empty() {
        #expect(Vocabulary(fileContent: "").entries.isEmpty)
        #expect(Vocabulary.empty.entries.isEmpty)
    }
}
