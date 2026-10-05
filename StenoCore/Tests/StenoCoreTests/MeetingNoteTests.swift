import Foundation
import Testing
import StenoCore

@Suite("Meeting note")
struct MeetingNoteTests {
    let rome = TimeZone(identifier: "Europe/Rome")!
    let stenoID = UUID(uuidString: "6F1C2A00-0000-4000-8000-000000000001")!
    /// 4 October 2026, 14:30 in Rome.
    let startedAt = Date(timeIntervalSince1970: 1_791_117_000)

    @Test("at start the note has frontmatter, the managed section and a section for personal notes")
    func initialContent() {
        let note = MeetingNote.initial(stenoID: stenoID, startedAt: startedAt, timeZone: rome)

        #expect(note.content == """
            ---
            steno_id: 6F1C2A00-0000-4000-8000-000000000001
            date: 2026-10-04T14:30
            tags: [meeting]
            ---
            %% steno:start %%
            ⏺ Recording in progress: the summary will appear here after you stop.
            %% steno:end %%

            ## Personal notes


            """)
    }

    @Test("rewriting the managed section leaves everything else untouched")
    func replaceManagedSection() {
        var note = MeetingNote(content: """
            ---
            steno_id: 1
            ---
            Note written above.
            %% steno:start %%
            ⏺ Recording in progress.
            %% steno:end %%

            ## Personal notes

            - ask Mario about the budget
            """)

        note.replaceManagedSection(with: "### Budget\n\nAll good.")

        #expect(note.content == """
            ---
            steno_id: 1
            ---
            Note written above.
            %% steno:start %%
            ### Budget

            All good.
            %% steno:end %%

            ## Personal notes

            - ask Mario about the budget
            """)
    }

    @Test("if one or both markers are missing, the managed section is recreated at the top of the body")
    func missingMarkers() {
        var note = MeetingNote(content: """
            ---
            steno_id: 1
            ---
            %% steno:start %%
            Text left after the user deleted the end marker.

            ## Personal notes

            - important point
            """)

        note.replaceManagedSection(with: "Summary.")

        #expect(note.content == """
            ---
            steno_id: 1
            ---
            %% steno:start %%
            Summary.
            %% steno:end %%

            Text left after the user deleted the end marker.

            ## Personal notes

            - important point
            """)
    }

    @Test("without frontmatter the recreated managed section goes at the top of the file")
    func missingMarkersWithoutFrontmatter() {
        var note = MeetingNote(content: "Just notes.\n")

        note.replaceManagedSection(with: "Summary.")

        #expect(note.content == "%% steno:start %%\nSummary.\n%% steno:end %%\n\nJust notes.\n")
    }

    @Test("markers inside a code block do not count: personal notes stay intact")
    func markersInsideCodeBlock() {
        var note = MeetingNote(content: """
            ---
            steno_id: 1
            ---
            %% steno:start %%
            Old summary.

            ## Personal notes

            ```
            %% steno:end %%
            ```
            """)

        note.replaceManagedSection(with: "New.")

        #expect(note.content == """
            ---
            steno_id: 1
            ---
            %% steno:start %%
            New.
            %% steno:end %%

            Old summary.

            ## Personal notes

            ```
            %% steno:end %%
            ```
            """)
    }

    @Test("a marker in the text being written is removed: it must not be able to close the managed section")
    func markersInBodyAreRemoved() {
        var note = MeetingNote(content: "%% steno:start %%\nOld.\n%% steno:end %%\n\nNotes.")

        note.replaceManagedSection(with: "Summary.\n%% steno:end %%\nMore.")

        #expect(note.content == "%% steno:start %%\nSummary.\nMore.\n%% steno:end %%\n\nNotes.")
    }

    @Test("a note with Windows line endings and a BOM is read correctly")
    func windowsLineEndings() {
        var note = MeetingNote(content: "\u{FEFF}---\r\nsteno_id: 1\r\n---\r\n%% steno:start %%\r\nOld.\r\n%% steno:end %%\r\n")

        note.setFrontmatter([(.language, "it")])
        note.replaceManagedSection(with: "New.")

        #expect(note.content == "---\nsteno_id: 1\nlanguage: it\n---\n%% steno:start %%\nNew.\n%% steno:end %%\n")
    }

    @Test("a frontmatter closing line with trailing spaces is recognised, horizontal rules in the body are not")
    func frontmatterCloseWithTrailingSpace() {
        var note = MeetingNote(content: "---\nsteno_id: 1\n---  \nBefore.\n\n---\n\nAfter.")

        note.setFrontmatter([(.language, "it")])

        #expect(note.content == "---\nsteno_id: 1\nlanguage: it\n---  \nBefore.\n\n---\n\nAfter.")
        #expect(note.personalNotes == "Before.\n\n---\n\nAfter.")
    }

    @Test("Steno updates its frontmatter keys and adds missing ones, leaving the user's keys alone")
    func frontmatter() {
        var note = MeetingNote(content: """
            ---
            steno_id: 1
            date: 2026-10-04T14:30
            project: Unipol
            tags:
              - meeting
              - client
            language:
              - en
            duration: 1m
            ---
            Body.
            """)

        note.setFrontmatter([
            (.duration, "47m"),
            (.language, "it"),
            (.transcript, MeetingNote.wikiLink("2026-10-04 1430 - Meeting (transcript)")),
        ])

        #expect(note.content == """
            ---
            steno_id: 1
            date: 2026-10-04T14:30
            project: Unipol
            tags:
              - meeting
              - client
            language: it
            duration: 47m
            transcript: "[[2026-10-04 1430 - Meeting (transcript)]]"
            ---
            Body.
            """)
    }

    @Test("a note without frontmatter gets one with Steno's keys")
    func frontmatterCreated() {
        var note = MeetingNote(content: "Body.")

        note.setFrontmatter([(.language, "it")])

        #expect(note.content == "---\nlanguage: it\n---\nBody.")
    }

    @Test("steno_id is read from the frontmatter only")
    func readsStenoIDFromFrontmatter() {
        let id = "6F1C2A00-0000-4000-8000-000000000001"

        #expect(MeetingNote(content: "---\nsteno_id: \(id)\n---\nBody.").stenoID == UUID(uuidString: id))
        #expect(MeetingNote(content: "---\ntitle: x\n---\nsteno_id: \(id)\n").stenoID == nil)
        #expect(MeetingNote(content: "steno_id: \(id)\n").stenoID == nil)
    }

    @Test("personal notes are the whole body outside the managed section, without the heading")
    func personalNotes() {
        let note = MeetingNote(content: """
            ---
            steno_id: 1
            ---
            Note written above.
            %% steno:start %%
            ### Summary
            Not the user's.
            %% steno:end %%

            ## Personal notes

            - ask Mario about the budget
            - risk: supplier is late

            """)

        #expect(note.personalNotes == """
            Note written above.

            - ask Mario about the budget
            - risk: supplier is late
            """)
    }

    @Test("a freshly created note has no personal notes")
    func noPersonalNotes() {
        let note = MeetingNote.initial(stenoID: stenoID, startedAt: startedAt, timeZone: rome)

        #expect(note.personalNotes.isEmpty)
    }

    @Test("at the end of Processing the note gets the Summary, the Transcript link and Steno's keys")
    func processingRecorded() {
        var note = MeetingNote.initial(stenoID: stenoID, startedAt: startedAt, timeZone: rome)

        note.recordProcessing(
            stenoID: stenoID, duration: 47 * 60 + 10, language: "it",
            transcriptName: "2026-10-04 1430 - Meeting (transcript)",
            summary: .written(text: "### Budget\n- Approved.", template: "Notes", provider: "Mistral EU")
        )

        #expect(note.content == """
            ---
            steno_id: 6F1C2A00-0000-4000-8000-000000000001
            date: 2026-10-04T14:30
            tags: [meeting]
            duration: 47m
            transcript: "[[2026-10-04 1430 - Meeting (transcript)]]"
            language: it
            template: Notes
            summary_provider: Mistral EU
            ---
            %% steno:start %%
            ### Budget
            - Approved.

            Full transcript: [[2026-10-04 1430 - Meeting (transcript)]]
            %% steno:end %%

            ## Personal notes


            """)
    }

    @Test("if the Summary fails the managed section shows the reason and the Transcript link")
    func summaryFailed() {
        var note = MeetingNote.initial(stenoID: stenoID, startedAt: startedAt, timeZone: rome)

        note.recordProcessing(
            stenoID: stenoID, duration: 60, language: "it", transcriptName: "T",
            summary: .failed(reason: "The provider answered with error 401: invalid key")
        )

        #expect(note.content.contains("""
            %% steno:start %%
            ⚠️ Summary not generated: The provider answered with error 401: invalid key

            Full transcript: [[T]]
            %% steno:end %%
            """))
        #expect(!note.content.contains("summary_provider"))
    }

    @Test("without a Summary Profile the managed section holds only the Transcript link, with no warning")
    func transcriptOnly() {
        var note = MeetingNote.initial(stenoID: stenoID, startedAt: startedAt, timeZone: rome)
        note.recordRegeneration(
            stenoID: stenoID, transcriptName: "T",
            summary: .written(text: "Old.", template: "Notes", provider: "OpenRouter")
        )

        note.recordProcessing(
            stenoID: stenoID, duration: 60, language: "it", transcriptName: "T",
            summary: .transcriptOnly
        )

        #expect(note.content.contains("""
            %% steno:start %%
            Full transcript: [[T]]
            %% steno:end %%
            """))
        #expect(!note.content.contains("template:"))
        #expect(!note.content.contains("summary_provider"))
    }

    @Test("the duration is written in minutes, with hours past 60 minutes", arguments: [
        (20.0, "1m"),
        (47.0 * 60 + 29, "47m"),
        (65.0 * 60, "1h 05m"),
    ])
    func duration(seconds: Double, expected: String) {
        var note = MeetingNote(content: "")

        note.recordProcessing(
            stenoID: stenoID, duration: seconds, language: nil, transcriptName: "T",
            summary: .failed(reason: "-")
        )

        #expect(note.content.contains("duration: \(expected)\n"))
        #expect(!note.content.contains("language:"))
    }

    @Test("if the user deleted the frontmatter, steno_id is restored")
    func stenoIDRestored() {
        var note = MeetingNote(content: "Just notes.")

        note.recordProcessing(
            stenoID: stenoID, duration: 60, language: "it", transcriptName: "T",
            summary: .failed(reason: "-")
        )

        #expect(note.stenoID == stenoID)
        #expect(note.personalNotes == "Just notes.")
    }

    @Test("if Processing fails the managed section shows the reason")
    func failureRecorded() {
        var note = MeetingNote.initial(stenoID: stenoID, startedAt: startedAt, timeZone: rome)

        note.recordFailure(stenoID: stenoID, reason: "Transcription failed: model unavailable.")

        #expect(note.content.contains("""
            %% steno:start %%
            ⚠️ Transcription failed: model unavailable.
            %% steno:end %%
            """))
    }

    @Test("Regeneration changes Summary, Template and provider but keeps duration, language and Transcript")
    func regeneration() {
        var note = MeetingNote.initial(stenoID: stenoID, startedAt: startedAt, timeZone: rome)
        note.recordProcessing(
            stenoID: stenoID, duration: 600, language: "it", transcriptName: "T",
            summary: .written(text: "Old.", template: "Notes", provider: "OpenRouter")
        )

        note.recordRegeneration(
            stenoID: stenoID, transcriptName: "T",
            summary: .written(text: "### Retro\nNew.", template: "Retro", provider: "Mistral EU")
        )

        #expect(note.content.contains("duration: 10m\n"))
        #expect(note.content.contains("language: it\n"))
        #expect(note.content.contains("template: Retro\n"))
        #expect(note.content.contains("summary_provider: Mistral EU\n"))
        #expect(note.content.contains("%% steno:start %%\n### Retro\nNew.\n\nFull transcript: [[T]]\n%% steno:end %%"))
        #expect(!note.content.contains("Old."))
    }
}
