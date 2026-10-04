import Foundation
import Testing
import StenoCore

@Suite("Fusione delle Tracce nella Trascrizione")
struct TranscriptTests {
    @Test("le battute delle due Tracce si alternano in ordine di tempo")
    func interleavesByStart() {
        let transcript = Transcript(utterances: [
            Utterance(track: .me, start: 12, end: 15, text: "Sì, sul primo punto."),
            Utterance(track: .others, start: 0, end: 10, text: "Buongiorno a tutti."),
            Utterance(track: .others, start: 20, end: 25, text: "Perfetto, andiamo avanti."),
        ])

        #expect(transcript.paragraphs == [
            Paragraph(track: .others, start: 0, text: "Buongiorno a tutti."),
            Paragraph(track: .me, start: 12, text: "Sì, sul primo punto."),
            Paragraph(track: .others, start: 20, text: "Perfetto, andiamo avanti."),
        ])
    }

    @Test("battute consecutive della stessa Traccia diventano un paragrafo con l'inizio della prima")
    func mergesConsecutiveSameTrack() {
        let transcript = Transcript(utterances: [
            Utterance(track: .others, start: 0, end: 4, text: "Buongiorno a tutti."),
            Utterance(track: .others, start: 5, end: 9, text: "Partiamo dal budget."),
            Utterance(track: .me, start: 10, end: 12, text: "Va bene."),
        ])

        #expect(transcript.paragraphs == [
            Paragraph(track: .others, start: 0, text: "Buongiorno a tutti. Partiamo dal budget."),
            Paragraph(track: .me, start: 10, text: "Va bene."),
        ])
    }

    @Test("dopo più di 30 secondi di pausa la stessa Traccia riparte con un nuovo paragrafo")
    func longPauseStartsNewParagraph() {
        let transcript = Transcript(utterances: [
            Utterance(track: .others, start: 0, end: 20, text: "Prima parte."),
            Utterance(track: .others, start: 45, end: 50, text: "Ancora vicino."),
            Utterance(track: .others, start: 420, end: 430, text: "Dopo cinque minuti."),
        ])

        #expect(transcript.paragraphs == [
            Paragraph(track: .others, start: 0, text: "Prima parte. Ancora vicino."),
            Paragraph(track: .others, start: 420, text: "Dopo cinque minuti."),
        ])
    }

    @Test("le battute fatte solo di annotazioni o spazi vengono scartate, il resto viene ripulito")
    func dropsAnnotations() {
        let transcript = Transcript(utterances: [
            Utterance(track: .others, start: 0, end: 4, text: "  Buongiorno a tutti. "),
            Utterance(track: .me, start: 5, end: 30, text: "[BLANK_AUDIO]"),
            Utterance(track: .me, start: 31, end: 60, text: " (Tolken pratar i en annan länk)"),
            Utterance(track: .me, start: 61, end: 62, text: "   "),
            Utterance(track: .others, start: 63, end: 66, text: "[Musica]"),
            Utterance(track: .others, start: 67, end: 70, text: "Partiamo dal budget."),
        ])

        #expect(transcript.paragraphs == [
            Paragraph(track: .others, start: 0, text: "Buongiorno a tutti."),
            Paragraph(track: .others, start: 67, text: "Partiamo dal budget."),
        ])
    }

    @Test("un paragrafo non supera i 60 secondi: oltre, la stessa Traccia riparte con un nuovo timestamp")
    func longMonologueIsSplit() {
        let transcript = Transcript(utterances: [
            Utterance(track: .others, start: 0, end: 25, text: "Uno."),
            Utterance(track: .others, start: 26, end: 50, text: "Due."),
            Utterance(track: .others, start: 51, end: 75, text: "Tre."),
            Utterance(track: .others, start: 76, end: 100, text: "Quattro."),
        ])

        #expect(transcript.paragraphs == [
            Paragraph(track: .others, start: 0, text: "Uno. Due. Tre."),
            Paragraph(track: .others, start: 76, text: "Quattro."),
        ])
    }

    @Test("il Markdown mette timestamp ed etichetta in grassetto, un paragrafo per blocco")
    func markdown() {
        let transcript = Transcript(utterances: [
            Utterance(track: .others, start: 0, end: 4, text: "Buongiorno a tutti."),
            Utterance(track: .me, start: 42.7, end: 45, text: "Sì, sul primo punto."),
            Utterance(track: .others, start: 3723, end: 3730, text: "Chiudiamo qui."),
        ])

        #expect(transcript.markdown == """
            **[00:00] Altri:** Buongiorno a tutti.

            **[00:42] Io:** Sì, sul primo punto.

            **[1:02:03] Altri:** Chiudiamo qui.

            """)
    }

    @Test("il file della Trascrizione nel Vault ha frontmatter con steno_id, link alla Nota e lingua")
    func vaultFile() {
        let transcript = Transcript(utterances: [
            Utterance(track: .others, start: 0, end: 4, text: "Buongiorno a tutti."),
        ])

        let file = transcript.vaultFile(
            stenoID: UUID(uuidString: "6F1C2A00-0000-4000-8000-000000000001")!,
            meetingNoteName: "2026-10-04 1430 - Riunione",
            language: "it"
        )

        #expect(file == """
            ---
            steno_id: 6F1C2A00-0000-4000-8000-000000000001
            riunione: "[[2026-10-04 1430 - Riunione]]"
            lingua: it
            ---
            **[00:00] Altri:** Buongiorno a tutti.

            """)
    }

    @Test("senza parlato la lingua non compare nel frontmatter")
    func vaultFileWithoutLanguage() {
        let file = Transcript(utterances: []).vaultFile(
            stenoID: UUID(uuidString: "6F1C2A00-0000-4000-8000-000000000001")!,
            meetingNoteName: "2026-10-04 1430 - Riunione",
            language: nil
        )

        #expect(file == """
            ---
            steno_id: 6F1C2A00-0000-4000-8000-000000000001
            riunione: "[[2026-10-04 1430 - Riunione]]"
            ---

            """)
    }

    @Test("il file della Trascrizione nel Vault si rilegge con paragrafi, tempi e lingua")
    func parseVaultFile() {
        let original = Transcript(utterances: [
            Utterance(track: .others, start: 0, end: 4, text: "Buongiorno a tutti."),
            Utterance(track: .me, start: 42.7, end: 45, text: "Sì, sul primo punto."),
            Utterance(track: .others, start: 3723, end: 3730, text: "Chiudiamo qui."),
        ])
        let file = original.vaultFile(
            stenoID: UUID(uuidString: "6F1C2A00-0000-4000-8000-000000000001")!,
            meetingNoteName: "2026-10-04 1430 - Riunione",
            language: "en"
        )

        let (parsed, language) = Transcript.parse(vaultFile: file)

        #expect(language == "en")
        #expect(parsed.paragraphs == [
            Paragraph(track: .others, start: 0, text: "Buongiorno a tutti."),
            Paragraph(track: .me, start: 42, text: "Sì, sul primo punto."),
            Paragraph(track: .others, start: 3723, text: "Chiudiamo qui."),
        ])
    }

    @Test("le righe aggiunte o corrette a mano nella Trascrizione restano nel paragrafo in cui sono")
    func parseEditedVaultFile() {
        let file = """
            ---
            steno_id: 1
            ---
            **[00:00] Altri:** Il budget è di 40 mila euro.
            (corretto a mano: 45 mila)

            **[00:12] Io:** Va bene.
            """

        let (parsed, language) = Transcript.parse(vaultFile: file)

        #expect(language == nil)
        #expect(parsed.paragraphs == [
            Paragraph(track: .others, start: 0, text: "Il budget è di 40 mila euro. (corretto a mano: 45 mila)"),
            Paragraph(track: .me, start: 12, text: "Va bene."),
        ])
    }
}
