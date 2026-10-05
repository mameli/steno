import Testing
import StenoCore

@Suite("Vocabulary variants in the Transcript")
struct TranscriptVocabularyTests {
    /// The text of the paragraphs of a Transcript built from Others Utterances, one second apart.
    private func paragraphs(_ vocabulary: String, _ sentences: String...) -> [String] {
        let utterances = sentences.enumerated().map {
            Utterance(track: .others, start: Double($0.offset), end: Double($0.offset) + 1, text: $0.element)
        }
        return Transcript(utterances: utterances, vocabulary: Vocabulary(fileContent: vocabulary)).paragraphs.map(\.text)
    }

    @Test("a variant is replaced by the term")
    func replacesVariant() {
        #expect(paragraphs("- Scaleway = scale uai", "Migriamo tutto su Scale Uai entro fine mese.")
            == ["Migriamo tutto su Scaleway entro fine mese."])
    }

    @Test("only whole words match: letters and digits next to a variant stop the match")
    func wholeWordsOnly() {
        #expect(paragraphs("- Kubernetes = kube", "Usiamo kube e kubectl, non kubeadm2.")
            == ["Usiamo Kubernetes e kubectl, non kubeadm2."])
    }

    @Test("an apostrophe or punctuation next to a variant does not stop the match, and case is ignored")
    func punctuationAndCase() {
        #expect(paragraphs("- Steno = absteno", "Ha chiamato l'absteno. Poi \"ABSTENO\", (absteno), absteno!")
            == ["Ha chiamato l'Steno. Poi \"Steno\", (Steno), Steno!"])
    }

    @Test("the longest variant wins, whatever the order in the file")
    func longestVariantWins() {
        #expect(paragraphs("""
            - WhisperKit = whisper
            - WhisperKit Pro = whisper kit pro
            """, "Con whisper kit pro e con whisper.")
            == ["Con WhisperKit Pro e con WhisperKit."])
    }

    @Test("a variant split across two Utterances of the same paragraph is found")
    func acrossUtterances() {
        #expect(paragraphs("- Scaleway = scale uai", "Migriamo su scale", "uai domani.")
            == ["Migriamo su Scaleway domani."])
    }

    @Test("a replacement is never replaced again")
    func noChainedReplacement() {
        #expect(paragraphs("""
            - Foo = bar
            - Bar = foo
            """, "bar e foo") == ["Foo e Bar"])
    }

    @Test("characters that mean something in a pattern are taken literally, in variants and terms")
    func specialCharacters() {
        #expect(paragraphs("- C++ = c plus plus", "Scriviamo in c plus plus.") == ["Scriviamo in C++."])
        #expect(paragraphs("- Costo $1 = costo $1 euro", "Il costo $1 euro.") == ["Il Costo $1."])
    }

    @Test("without a Vocabulary the text is untouched")
    func emptyVocabulary() {
        #expect(paragraphs("", "Scale Uai e absteno.") == ["Scale Uai e absteno."])
    }
}
