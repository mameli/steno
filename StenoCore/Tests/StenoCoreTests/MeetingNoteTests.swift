import Foundation
import Testing
import StenoCore

@Suite("Nota della Riunione")
struct MeetingNoteTests {
    let rome = TimeZone(identifier: "Europe/Rome")!
    let stenoID = UUID(uuidString: "6F1C2A00-0000-4000-8000-000000000001")!
    /// 4 ottobre 2026, 14:30 a Roma.
    let startedAt = Date(timeIntervalSince1970: 1_791_117_000)

    @Test("all'avvio la nota ha frontmatter, Zona gestita e la sezione per le Note personali")
    func initialContent() {
        let note = MeetingNote.initial(stenoID: stenoID, startedAt: startedAt, timeZone: rome)

        #expect(note.content == """
            ---
            steno_id: 6F1C2A00-0000-4000-8000-000000000001
            data: 2026-10-04T14:30
            tags: [riunione]
            ---
            %% steno:inizio %%
            ⏺ Registrazione in corso: il Riepilogo comparirà qui dopo lo stop.
            %% steno:fine %%

            ## Note personali


            """)
    }

    @Test("riscrivere la Zona gestita lascia intatto tutto il resto")
    func replaceManagedSection() {
        var note = MeetingNote(content: """
            ---
            steno_id: 1
            ---
            Appunto scritto sopra.
            %% steno:inizio %%
            ⏺ Registrazione in corso.
            %% steno:fine %%

            ## Note personali

            - chiedere a Mario il budget
            """)

        note.replaceManagedSection(with: "## Riepilogo\n\nTutto ok.")

        #expect(note.content == """
            ---
            steno_id: 1
            ---
            Appunto scritto sopra.
            %% steno:inizio %%
            ## Riepilogo

            Tutto ok.
            %% steno:fine %%

            ## Note personali

            - chiedere a Mario il budget
            """)
    }

    @Test("se i marcatori mancano, anche uno solo, la Zona gestita viene ricreata in cima al corpo")
    func missingMarkers() {
        var note = MeetingNote(content: """
            ---
            steno_id: 1
            ---
            %% steno:inizio %%
            Testo rimasto dopo che l'utente ha cancellato il marcatore di fine.

            ## Note personali

            - punto importante
            """)

        note.replaceManagedSection(with: "Riepilogo.")

        #expect(note.content == """
            ---
            steno_id: 1
            ---
            %% steno:inizio %%
            Riepilogo.
            %% steno:fine %%

            Testo rimasto dopo che l'utente ha cancellato il marcatore di fine.

            ## Note personali

            - punto importante
            """)
    }

    @Test("senza frontmatter la Zona gestita ricreata va in cima al file")
    func missingMarkersWithoutFrontmatter() {
        var note = MeetingNote(content: "Solo appunti.\n")

        note.replaceManagedSection(with: "Riepilogo.")

        #expect(note.content == "%% steno:inizio %%\nRiepilogo.\n%% steno:fine %%\n\nSolo appunti.\n")
    }

    @Test("Steno aggiorna le sue chiavi del frontmatter e aggiunge quelle mancanti, lasciando quelle dell'utente")
    func frontmatter() {
        var note = MeetingNote(content: """
            ---
            steno_id: 1
            data: 2026-10-04T14:30
            progetto: Unipol
            tags:
              - riunione
              - cliente
            lingua:
              - en
            durata: 1m
            ---
            Corpo.
            """)

        note.setFrontmatter([
            (.duration, "47m"),
            (.language, "it"),
            (.transcript, MeetingNote.wikiLink("2026-10-04 1430 - Riunione (trascrizione)")),
        ])

        #expect(note.content == """
            ---
            steno_id: 1
            data: 2026-10-04T14:30
            progetto: Unipol
            tags:
              - riunione
              - cliente
            lingua: it
            durata: 47m
            trascrizione: "[[2026-10-04 1430 - Riunione (trascrizione)]]"
            ---
            Corpo.
            """)
    }

    @Test("una nota senza frontmatter ne riceve uno con le chiavi di Steno")
    func frontmatterCreated() {
        var note = MeetingNote(content: "Corpo.")

        note.setFrontmatter([(.language, "it")])

        #expect(note.content == "---\nlingua: it\n---\nCorpo.")
    }

    @Test("le Note personali sono tutto il corpo fuori dalla Zona gestita, senza l'intestazione")
    func personalNotes() {
        let note = MeetingNote(content: """
            ---
            steno_id: 1
            ---
            Appunto scritto sopra.
            %% steno:inizio %%
            ## Riepilogo
            Non è dell'utente.
            %% steno:fine %%

            ## Note personali

            - chiedere a Mario il budget
            - rischio: fornitore in ritardo

            """)

        #expect(note.personalNotes == """
            Appunto scritto sopra.

            - chiedere a Mario il budget
            - rischio: fornitore in ritardo
            """)
    }

    @Test("una nota appena creata non ha Note personali")
    func noPersonalNotes() {
        let note = MeetingNote.initial(stenoID: stenoID, startedAt: startedAt, timeZone: rome)

        #expect(note.personalNotes.isEmpty)
    }

    @Test("i marcatori dentro un blocco di codice non contano: le Note personali restano intatte")
    func markersInsideCodeBlock() {
        var note = MeetingNote(content: """
            ---
            steno_id: 1
            ---
            %% steno:inizio %%
            Vecchio riepilogo.

            ## Note personali

            ```
            %% steno:fine %%
            ```
            """)

        note.replaceManagedSection(with: "Nuovo.")

        #expect(note.content == """
            ---
            steno_id: 1
            ---
            %% steno:inizio %%
            Nuovo.
            %% steno:fine %%

            Vecchio riepilogo.

            ## Note personali

            ```
            %% steno:fine %%
            ```
            """)
    }

    @Test("una nota con a capo Windows e BOM viene letta correttamente")
    func windowsLineEndings() {
        var note = MeetingNote(content: "\u{FEFF}---\r\nsteno_id: 1\r\n---\r\n%% steno:inizio %%\r\nVecchio.\r\n%% steno:fine %%\r\n")

        note.setFrontmatter([(.language, "it")])
        note.replaceManagedSection(with: "Nuovo.")

        #expect(note.content == "---\nsteno_id: 1\nlingua: it\n---\n%% steno:inizio %%\nNuovo.\n%% steno:fine %%\n")
    }

    @Test("la chiusura del frontmatter con spazi in fondo viene riconosciuta, le righe orizzontali del corpo no")
    func frontmatterCloseWithTrailingSpace() {
        var note = MeetingNote(content: "---\nsteno_id: 1\n---  \nPrima.\n\n---\n\nDopo.")

        note.setFrontmatter([(.language, "it")])

        #expect(note.content == "---\nsteno_id: 1\nlingua: it\n---  \nPrima.\n\n---\n\nDopo.")
        #expect(note.personalNotes == "Prima.\n\n---\n\nDopo.")
    }

    @Test("lo steno_id si legge solo dal frontmatter")
    func readsStenoIDFromFrontmatter() {
        let id = "6F1C2A00-0000-4000-8000-000000000001"

        #expect(MeetingNote(content: "---\nsteno_id: \(id)\n---\nCorpo.").stenoID == UUID(uuidString: id))
        #expect(MeetingNote(content: "---\ntitolo: x\n---\nsteno_id: \(id)\n").stenoID == nil)
        #expect(MeetingNote(content: "steno_id: \(id)\n").stenoID == nil)
    }

    @Test("a fine Elaborazione la nota riceve durata, lingua, provider e link alla Trascrizione")
    func transcriptionRecorded() {
        var note = MeetingNote.initial(stenoID: stenoID, startedAt: startedAt, timeZone: rome)

        note.recordTranscription(
            stenoID: stenoID, duration: 47 * 60 + 10, language: "it",
            provider: "Locale", transcriptName: "2026-10-04 1430 - Riunione (trascrizione)"
        )

        #expect(note.content == """
            ---
            steno_id: 6F1C2A00-0000-4000-8000-000000000001
            data: 2026-10-04T14:30
            tags: [riunione]
            durata: 47m
            provider_trascrizione: Locale
            trascrizione: "[[2026-10-04 1430 - Riunione (trascrizione)]]"
            lingua: it
            ---
            %% steno:inizio %%
            Trascrizione pronta: [[2026-10-04 1430 - Riunione (trascrizione)]]
            %% steno:fine %%

            ## Note personali


            """)
    }

    @Test("la durata si scrive in minuti, con le ore oltre i 60 minuti", arguments: [
        (20.0, "1m"),
        (47.0 * 60 + 29, "47m"),
        (65.0 * 60, "1h 05m"),
    ])
    func duration(seconds: Double, expected: String) {
        var note = MeetingNote(content: "")

        note.recordTranscription(stenoID: stenoID, duration: seconds, language: nil, provider: "Locale", transcriptName: "T")

        #expect(note.content.contains("durata: \(expected)\n"))
        #expect(!note.content.contains("lingua:"))
    }

    @Test("se l'utente ha cancellato il frontmatter, lo steno_id viene ripristinato")
    func stenoIDRestored() {
        var note = MeetingNote(content: "Solo appunti.")

        note.recordTranscription(stenoID: stenoID, duration: 60, language: "it", provider: "Locale", transcriptName: "T")

        #expect(note.stenoID == stenoID)
        #expect(note.personalNotes == "Solo appunti.")
    }

    @Test("se l'Elaborazione fallisce la Zona gestita mostra il motivo")
    func failureRecorded() {
        var note = MeetingNote.initial(stenoID: stenoID, startedAt: startedAt, timeZone: rome)

        note.recordFailure(stenoID: stenoID, reason: "Trascrizione non riuscita: modello non disponibile.")

        #expect(note.content.contains("""
            %% steno:inizio %%
            ⚠️ Trascrizione non riuscita: modello non disponibile.
            %% steno:fine %%
            """))
    }
}
