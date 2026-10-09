# Steno: v1 specification

Terms in **bold** are defined in [CONTEXT.md](../CONTEXT.md). Architecture decisions are in [docs/adr](adr/).

## Goal

Record a **Meeting** on the Mac, produce its **Transcript** and **Summary** with **Providers** chosen by the user (local or in the EU) and write everything into the Obsidian **Vault**, without data leaving the EU ([ADR 0001](adr/0001-data-stays-in-the-eu.md)).

Personal use, one machine (M3 Pro, 18 GB, macOS 26). Meetings in Italian or English, one language per Meeting.

## Scope

**In v1**
- Menu bar app: start/stop, global shortcut, **Template** choice
- Capture in Call mode: **Tracks** Me (microphone, with echo cancellation) and Others (system audio)
- Local WhisperKit transcription in Segments during the call
- Language detected automatically or forced
- **Provider profiles** for the Summary, OpenAI-compatible adapter, keys in the Keychain, minimal Settings window
- **Meeting note** created at start and opened in Obsidian; **Managed section**; Transcript in a separate file
- Templates read from the Vault, **Regeneration**, Retry
- **Vocabulary** in the Vault: variants replaced in the Transcript, terms in the Summary prompt ([ADR 0005](adr/0005-vocabulary-without-llm-pass-or-engine-biasing.md))
- Recording kept for 7 days, **Processing** queue
- English user interface with Italian translation (string catalogs); English Vault format

**Out of v1** (most likely first)
1. Calendar (title and participants from EventKit)
2. Remote transcription (local is enough: 12 minutes in 50 seconds on an M3 Pro); Profiles will then also get the transcription Role
3. Room capture mode (microphone only, for in-person meetings)
4. "Looks like a call" notification when an app grabs the microphone
5. Real diarization (Person 1, 2…)
6. Ready-made Provider presets
7. Notarized distribution (paid Developer ID). v1 is distributed as a zip on GitHub Releases, signed with a self-signed certificate (`scripts/release.sh`): other Macs open it with "Open Anyway"
8. Automatic stop on silence at the end of the call (was phase 6)
9. Vocabulary for the recognition engines (a prompt for Whisper; CTC boosting for Parakeet, tried and not usable in Italian). See ADR 0005.
10. An LLM pass that corrects the Transcript before the Summary (only if the variants and the Summary prompt prove not enough)

## Main flow

1. **Start** (click or shortcut). Steno:
   - creates the Meeting identifier and the Recording folder and starts capturing the two Tracks (first, so no audio is lost);
   - creates the Meeting note `<Vault>/Meetings/2026-10-04 1430 - Meeting.md` (see [structure](#meeting-note));
   - opens it in Obsidian with `obsidian://open?path=<absolute path>`.
2. **During the call**: the user writes **Personal notes** in the note. Segments already closed are transcribed in the background. The Template can be changed from the menu bar; the Summary Profile is the one active at the start.
3. **Stop** (click or shortcut). The Meeting enters the Processing queue and another Meeting can start right away.
4. **Processing** (one at a time, in arrival order):
   1. completes the Transcript (the last Segments);
   2. reads the Meeting note again and extracts the Personal notes;
   3. generates Summary and title with the Summary Profile (with *Transcript* chosen instead of a Profile: no Summary, no Template, no title);
   4. renames the note with the title, if the user has not renamed or moved it (the Transcript is then named after the renamed note; an existing Transcript is never renamed);
   5. writes the Transcript file;
   6. rewrites the Managed section and Steno's frontmatter keys;
   7. notifies "Summary ready" (click → opens the note in Obsidian).
5. If a step fails: the Managed section shows `⚠️ Summary not generated: <reason>`. The Meeting stays in "Recent meetings" with **Retry**. No fallback to another Provider.

## Audio capture

- **Others**: global Core Audio process tap (`CATapDescription`, all processes: Steno plays no audio, so there is no need to exclude it) + aggregate device containing **only the tap**. An aggregate with the speakers as main device stops receiving audio when the microphone's voice processing is active. It starts before the microphone. Requires `NSAudioCaptureUsageDescription`: the first time macOS shows the "System Audio Recording Only" prompt and the start waits for the answer.
- **Me**: `AVAudioEngine` on the default microphone with `setVoiceProcessingEnabled(true)` for echo cancellation. With voice processing the microphone delivers 9 channels: only channel 0, already cleaned, is kept. The engine's output branch must not be connected, otherwise the start fails (-10875). Requires `NSMicrophoneUsageDescription`. The engine stops whenever the audio configuration changes: voice processing itself switches Bluetooth headsets (AirPods) to call mode right after the start, and the default microphone can change during a Meeting (AirPods connected or removed). Steno first starts the same engine again (a new engine would switch the headset back to music mode and loop); if no audio arrives within 2 seconds, the microphone really changed and a new engine takes the new default one (at most 5 restarts a minute) and the hole, usually a second or two, is filled with silence so the Track stays aligned with Others. Any hole over half a second in a Track is filled the same way.
- Each Track is written in **5-minute Segments** (`me-000.m4a`, `others-000.m4a`, …), AAC mono 16 kHz. Reasons: a crash loses at most one Segment; closed Segments are transcribed during the call; files stay under remote Providers' upload limits.
- The two Tracks share the start clock: every Segment records its offset from the start of the Meeting. Each Track's Segment list (`me-segments.json`, `others-segments.json`) is updated whenever a Segment opens, so offsets survive a crash; at the stop it goes into `recording.json`, which is written even if a Track was interrupted.

**Stop on silence**: out of v1 by the user's choice (the Meeting is always stopped by hand, from the menu or with ⌃⌥⌘R).

## Transcription

- Each Track is transcribed separately. The Utterances of the two Tracks are sorted by start time and merged into paragraphs (rules below).
- A Segment that cannot be transcribed does not block the others: the Transcript is written with a gap and the error is reported.
- Whisper only gets the **speech ranges** of each Segment: half-second windows with RMS above 0.004, pauses under 2 seconds absorbed, a quarter of a second of margin on each side. On silence, echo residue and distant voices Whisper makes up sentences ("Grazie.", dozens of times in the phase 1 test). Annotations such as `[BLANK_AUDIO]` or sentences in parentheses are dropped anyway. A speech range with at most 3 seconds of sound (pauses and margins excluded) whose whole text is a stock subtitle sentence ("Grazie.", "Thank you.", "Sottotitoli creati dalla comunità Amara.org"…) is dropped too: it is Whisper's reaction to a short noise such as a notification sound. A real isolated "Grazie." from the others is lost with it. Echo leaked into the microphone (speakers without headphones, while echo cancellation is still adapting) is removed when the Transcript is built: a run of Me Utterances (pauses under 2 seconds) of at least 3 words, 80% of which appear in the same order in what Others say within 5 seconds, is dropped. What echo cancellation leaves of the others' voice is too garbled for that: it peaks around -40 dBFS, against -10 to -25 for the user's own voice, and recognition turns it into random words in any language ("The five.", "Oh yeah"). Me Utterances whose peak level (RMS of the loudest 100 ms) is more than 25 dB below the loudest Me Utterance of the Meeting are dropped too; the reference is the loudest one because in a Meeting where the user barely speaks most Me Utterances are residue. On 13 real Meetings this removed 205 of 249 Me Utterances in the worst one and kept the faintest real replies by over 10 dB. Both are applied when the Transcript is built, not to the cache, so Retry cleans older Recordings too.
- **Speakers**: the Others Track is diarized locally after its Segments are transcribed, with FluidAudio's offline pipeline (pyannote community-1, models of about 22 MB downloaded on first use to `Steno/Models/fluidaudio/speaker-diarization`). The Segments are joined in one temporary file, each at its start, so a voice keeps its number across Segments. Each Others Utterance takes the voice whose turns cover most of it; one that overlaps none (a short "ok" the diarizer did not count as speech) takes the voice of a turn within 2 seconds, otherwise it stays *Others*. Voices are numbered *Speaker 1*, *Speaker 2*… in the order they first speak in the Transcript. Diarization runs at every Processing, not cached (a 40-minute Meeting takes under 10 seconds); if it fails the Transcript keeps *Others* and the error is a warning. The Me Track is not diarized: it is one person.
- A Transcript paragraph joins consecutive Utterances of the same Track and Speaker, but breaks after a pause longer than 30 seconds or when an Utterance starts more than 60 seconds after the paragraph's start: a new timestamp about every minute (a Whisper Utterance is at most 30 seconds long).
- The **Vocabulary** variants are replaced with the term in the paragraph text, once the Utterances are merged (so a variant that crosses two Utterances of the same paragraph is found), when the Transcript is built, not in the cache: like the echo removal, a Retry with the audio uses the Vocabulary of that moment. A variant matches as a whole word (letters and digits on either side stop a match, an apostrophe or punctuation does not: `l'absteno` → `l'Steno`), ignoring case; the longest variant wins; the replacement is the term as written in the Vocabulary. It also applies with *Transcript* chosen as Summary Profile. A Regeneration does not touch the text already in the Vault.
- The result of each Segment (language and Utterances) is saved next to the audio (`me-000.m4a.json`), so a new Processing does not transcribe again what is done.
- **Models**: Large v3 Turbo (`openai_whisper-large-v3-v20240930_turbo_632MB`, 646 MB, default), Large v3 Turbo full (`…_turbo`, 1.6 GB) Small (`openai_whisper-small_216MB`, 217 MB) and NVIDIA Parakeet TDT 0.6B v3 (through FluidAudio, about 490 MB), all multilingual. Parakeet cannot be held to a language: it picks one per stretch of speech and on short, unclear replies can switch (e.g. to English or Portuguese); the Meeting language is read from its text with macOS's language recogniser. Its tokens are joined into sentences at final punctuation or after a 1.5 s pause. Settings → *Transcription* downloads them (with a percentage, then "Preparing…" while Parakeet is compiled), chooses the one in use and deletes the others; the model is changed rarely, so the menu bar does not offer it. A Meeting keeps the model it started with; Retry uses the one in use. The per-Segment cache records the model: Segments transcribed by another model are transcribed again.
- **Local**: WhisperKit; the model in use is downloaded on first use to `~/Library/Application Support/Steno/Models` and prepared while the first Meeting is in progress. The menu shows "Downloading transcription model… N%", then "Preparing transcription model, first time only" (macOS compiles it for the Neural Engine: a few minutes, once) or, on later launches, "Loading transcription model…". A marker file written after the download makes an interrupted download resume instead of loading a partial model.
- **Language**: `auto` or forced `it`/`en` (`defaults write dev.mameli.steno language it`). Detection runs on up to 30 seconds of speech only (the voice ranges, no silence) of the first Segment that has any, from either Track, picking only between Italian and English, and holds for the whole Meeting. It is locked only when there are at least 10 seconds of speech: on a short "ok" Whisper can pick the wrong language and then *translate* instead of transcribing. With less speech the detected language is provisional: it applies to that Segment only, detection is tried again on the next one, and at the end of Processing the Segments transcribed with a provisional language different from the locked one are transcribed again. If the language is never locked (very little speech in the whole Meeting) the provisional results stay. Detecting on the first 30 seconds of audio is not enough: in the real phase 1 test the Me Track started with 80 seconds of near silence and Whisper classified it as Swedish. The language used is saved in every Segment's cache; if a different language is forced later, the Segment is transcribed again.
- **Remote** (after v1): `POST {baseURL}/audio/transcriptions` (multipart, one Segment per request) through the OpenAI-compatible adapter. Only at the stop: during the call the audio never leaves the Mac.

File `<Vault>/Meetings/Transcripts/2026-10-04 1430 - <Title> (transcript).md` (a copy without frontmatter stays in `transcript.md` in the Recording folder while the audio is there). A new Processing of the same Meeting overwrites the existing file, found through `steno_id`:

```markdown
---
steno_id: 6F1C…
meeting: "[[2026-10-04 1430 - Title]]"
language: it
---
**[00:00] Speaker 1:** Buongiorno a tutti, partiamo dal…

**[00:42] Me:** Sì, sul primo punto…

**[00:47] Speaker 2:** Ok.
```

Transcripts written before Speakers existed have *Others* instead and still read back.

## Meeting note

```markdown
---
steno_id: 6F1C…
date: 2026-10-04T14:30
duration: 47m
template: Notes
language: it
summary_provider: Mistral EU
transcript: "[[2026-10-04 1430 - Title (transcript)]]"
tags: [meeting]
---
%% steno:start %%
⏺ Recording in progress: the summary will appear here after you stop.   ← then the Summary
%% steno:end %%

## Personal notes

```

Rules:
- Steno rewrites **only** the text between `%% steno:start %%` and `%% steno:end %%` and **its own** frontmatter keys (`duration`, `language`, `summary_provider`, `template`, `transcript`). Keys added by the user stay. `date` and `tags` are written only at creation: from then on they belong to the user. `steno_id` is restored at every update if the user deleted it, otherwise the note could not be found again.
- `steno_id` counts only in the frontmatter (the same text in the body does not identify the note). Managed section markers inside code blocks do not count. Notes with Windows line endings or a BOM are read correctly and rewritten with `\n` line endings.
- Steno updates the note in place (it does not replace the file), checking that it did not change between read and write: if Obsidian saved it meanwhile, Steno reads it again and reapplies the change.
- If Processing fails, the Managed section shows `⚠️ <reason>` instead of staying on "Recording in progress".
- Between creation and the end of Processing Steno does not write to the note (no intermediate "Processing" state): progress shows in the menu bar.
- If the Vault is not reachable at start (volume not mounted, folder moved) the Meeting is recorded anyway and the note is created at the end of Processing. The same happens if the user deletes the note during the Meeting.
- **Personal notes** = the whole body outside the Managed section, without the `## Personal notes` heading. If empty, the Summary relies on the Transcript only.
- If the markers were deleted, Steno recreates them at the top of the body, without deleting anything.
- The note is found through `steno_id`: first at the known path, otherwise by searching the Meetings folder. If the user renamed or moved it, Steno does not rename it.
- When a name already exists a ` (2)` suffix is added.
- Without the calendar, `participants` is not written in v1.
- Steno writes only once Processing is over, i.e. minutes after the stop, to avoid conflicts with edits still open in Obsidian.

## Template

- Folder `<Vault>/Meetings/_Templates/`. The default Template is `Notes.md`, Granola style: topics in the order they were discussed, each with a `###` heading and bullets with sub-bullets (reasons, people, figures, links), then `### Next steps` with `- [ ] What to do (Who)` and the context below. No opening summary and no fixed sections. Steno creates it at app launch and when the Vault is chosen, if the folder is empty or if the default Template no longer exists (then the default goes back to Notes).
- Format: frontmatter with `name` and `summary_language` (any language code such as `it`, `en`, `fr`, `de`; `auto` or missing = the Meeting's language). The body, i.e. free-form instructions and heading structure, is passed to the model as it is.
- The Template is chosen at start (default from Settings) and can change until the stop.
- In Settings, Templates section: list, default Template, "New Template" (name → file created from Notes and opened in Obsidian), "Open in Obsidian", "Delete" (asks for confirmation, then moves the file to the Trash with no further message: the row disappearing is enough; if it was the default, Notes becomes the default again; Notes itself cannot be deleted). A Meeting whose Template is gone uses the Vault's Notes, as the user edited it; only without it the built-in text. New files (Templates, Meeting notes) are opened in Obsidian after a second, otherwise Obsidian may not have noticed them yet and answers "file not found". The text is written in Obsidian: Steno has no editor.

## Vocabulary

The names, acronyms and technical words that recognition gets wrong, in the file `<Vault>/Meetings/_Vocabulary.md`, written in Obsidian like the Templates. It is global (it applies to every Meeting) and is read at every Processing: a change counts from the next Meeting, or from a Retry with the audio. If the file is missing or empty everything works as before; without a Vault there is no Vocabulary. Why it works this way and not through the engines or an LLM pass: [ADR 0005](adr/0005-vocabulary-without-llm-pass-or-engine-biasing.md).

One entry per line, as a Markdown list item:

```markdown
- Steno = absteno, steno | our app for recording meetings
- Scaleway = scale uai
- Mameli
```

- `Term` is the correct form. After `=`, comma-separated, the variants usually heard instead (optional). After `|` a short description (optional). Extra spaces are ignored.
- Lines that do not start with `- ` (headings, notes, blank lines) are ignored, so the file can hold free text.
- Two entries with the same term: the first one counts. The same variant in two entries: the first one counts. A variant equal to its own term is ignored.
- The variants are used for the substitution in the Transcript ([Transcription](#transcription)). The terms, variants and descriptions go to the Summary prompt ([Summary](#summary)). The recognition engines get nothing.

## Summary

- `POST {baseURL}/chat/completions` with:
  - **fixed system prompt** (in English): write the summary in the language stated explicitly ("Write the summary in Italian", whatever language the Template is written in), follow the Template's structure and instructions, do not invent, end every bullet with the time of the Transcript passage it comes from and leave out what has none, summarise a Transcript cut mid-sentence only up to where it stops (also in partial requests), attribute to Me/Others, Me is the user's macOS full name (`NSFullUserName`) and is written by name, never as "Me", actions as a checklist in the Template's format (otherwise `- [ ] who: what (when)`), give priority to the topics of the Personal notes;
  - **user message**: Template, Personal notes, Transcript.
  - **Vocabulary**, if there is one: a block in the system prompt in every request (single, partial, group, merge and title) with each term, its variants ("may be written as …") and its description. The prompt says the Transcript comes from automatic speech recognition and may spell names and technical terms wrong; the model uses the Vocabulary and the context to write them right, and corrects only when it is sure, otherwise it leaves the text as it is. It does not turn the Transcript into something else: the existing rule *do not invent* still holds.
- **Cited times**: Steno removes them from the final Summary (`[12:34]`, `[03:10] [07:45]`, `([1:02:45])`, `[04:00-06:30]`), so they tie every point to the Transcript without being shown; the partial summaries keep them for the merge. Checkboxes, wikilinks and Markdown links stay.
- **Summary language**: the Template's `summary_language` (any language), otherwise the Meeting's detected language, otherwise (no speech, or detection failed) Italian.
- **Title**: a second short call on the Summary ("at most 6 words, no date", in the Summary language), cleaned of headings, "Title:" prefixes, quotes, bold and final punctuation. If no title comes back the note keeps its provisional name: it is not an error.
- **Managed section**: the Summary followed by `Full transcript: [[…]]`. With *Transcript* chosen as Summary Profile it holds only the `Full transcript: [[…]]` link, with no warning, and the note keeps its provisional name. If the Summary fails (Provider error, Meeting without speech) it shows `⚠️ Summary not generated: <reason>` and the Transcript link, which stays usable. Managed section markers in the model's reply are removed.
- **Token estimate**: about 3 characters per token, with 4,096 tokens reserved for the reply; a block never splits a Transcript paragraph.
- **Long Meetings**: every Summary Profile has a *max context* field. If Transcript + notes + Template exceed it, the Transcript is split into blocks, every block is summarised and the partial summaries are merged with the Template (in groups, if even the merge does not fit).
- **Regeneration**: what Retry does once the audio is deleted. Reads the current Transcript and Personal notes again from the Vault and rewrites only the Managed section; a note still with its provisional name gets the title. To summarise again with another Template or Profile, choose them in the menu and Retry.

## Profiles and settings

**Profile** (v1: Summary only): name, base URL, API key (in the Keychain, optional for local servers), model, max context. Examples: "Local llama.cpp" (`http://localhost:8080/v1`), "Mistral EU" (`https://api.mistral.ai/v1`). Transcription is always local (WhisperKit). A Profile outside the EU (e.g. OpenRouter) is allowed only for development with test recordings: Steno does not prevent it, the choice stays with the user (exception recorded in ADR 0001). The Profile is fixed when the Meeting starts; if it is deleted before the Summary (its key goes with it), the Summary fails saying so, and Retry with another Profile fixes it. A new Profile is not made active by itself. The URL must be `https://`; `http://` is allowed only for servers on this Mac (`localhost`, `127.0.0.1`, `::1`): to any other machine, even on the local network, key and Transcript would travel readable.

**Settings** (UserDefaults; secrets in the Keychain). In the v1 Settings window:
- Open at login (a login item registered with macOS, also visible in System Settings → General → Login Items)
- Vault path
- Templates and default Template
- Summary Profiles and active Profile (with "Test connection")
- Vocabulary: number of entries and "Open Vocabulary" (creates the file with an example if it is missing, then opens it in Obsidian)
- Transcription: models (Download, Use, Delete; the one in use cannot be deleted)
- Recordings: days the audio is kept (default 7), space used, "Show in Finder", "Delete audio" (all concluded Meetings, with confirmation). A shorter retention applies at the next cleanup, not on the spot.

From the terminal only (`defaults write dev.mameli.steno language it`), to move into the Settings window if it is needed: the Meeting language (`auto` | `it` | `en`). Echo cancellation is always on.

The global shortcut is fixed: ⌃⌥⌘R. If another app already uses it, the menu says so.

The folders are fixed: `Meetings/`, `Meetings/Transcripts/`, `Meetings/_Templates/`; the Vocabulary is the fixed file `Meetings/_Vocabulary.md`. The Italian format of earlier development versions is not supported: those notes and Recordings were deleted.

## Menu bar

- **Idle**: Start meeting (shortcut) · Template ▸ (hidden when the Summary Profile is *Transcript*) · Summary Profile ▸ (*Transcript* or a Profile) · Recent meetings ▸ (Open note · Retry) · Settings… · Quit
- **Recording**: only a red dot in the bar; in the menu "Recording · duration" · Stop · Template ▸ · Settings…
- **Processing**: hourglass in the bar; in the menu "Processing… (N more queued)"

The interface is in English in the code and translated to Italian in `Steno/Localizable.xcstrings` and `Steno/InfoPlist.xcstrings`: macOS picks the language of the system. Error messages from `StenoCore` are looked up in the app's catalog too. The structure Steno writes into the Vault (headings, markers, keys, labels, status lines such as "Summary not generated:") is always in English; the error detail after it follows the app language, like the menu.

## State and retention

- `~/Library/Application Support/Steno/Recordings/<steno_id>/`: audio Segments, per-Segment transcription cache (language, whether it was reliable, Utterances), `recording.json` (start, end, Segments) and `processing.json` (status: recording, queued, processing, regenerating, completed, failed with reason; Template; Profile fixed at start; note path).
- Persistent Processing queue, one Meeting at a time: at app restart queued or in-progress Processing resumes, oldest first. A Recording interrupted by a crash is rebuilt from the Segment lists and queued: only the Segment open at the crash is lost (an unclosed AAC file is unreadable).
- An unreadable Segment is a warning ("Incomplete transcript"), not a failure: the Summary is generated with what there is.
- At app launch and every day: deletion of the audio (and transcription caches) of Meetings older than 7 days that are processed or failed, never of those recording, queued, processing or regenerating. `recording.json` and `processing.json` stay: the Meeting stays among the recent ones and Retry makes the Summary again from the Transcript in the Vault. About 20 MB of audio per hour of Meeting (AAC mono 16 kHz, about 180 KB per minute for each Track with sound).
- **Notifications**: "Summary ready" (click → note in Obsidian) or "Processing failed" with the reason.
- **Global shortcut** ⌃⌥⌘R: starts or stops the Meeting from any app.
- **Recent meetings** (the last 5): Open note · Retry. A concluded Meeting whose note was deleted from the Vault is not listed (its Recording stays until the audio expires); the name shown is the note's current one. The list is read again whenever the menu opens. Retry uses the Template and Summary Profile chosen in the menu at that moment, which become the Meeting's. While the audio is there it redoes the whole Processing (Segments already transcribed come from the cache); without it, it is a Regeneration from the Transcript in the Vault. Retry appears only for concluded Meetings (completed or failed), never for one recording or queued. A Regeneration interrupted by a restart is not repeated: the Meeting goes back to completed with the previous Summary.
- Without a configured Vault Processing stops at the Transcript and the notification says "Transcript ready", not "Summary ready".

## Project structure

- **Xcode app** `Steno` (SwiftUI, `MenuBarExtra`, macOS 15 target, Personal Team signing): audio capture, WhisperKit, notifications, shortcut, Keychain, UI.
- **Local Swift package** `StenoCore`, testable with `swift test` and without AppKit or AVFoundation: Segments → Transcript merging, reading and writing the Meeting note (Managed section, frontmatter, lookup by `steno_id`), Template parsing, prompt building and chunking, OpenAI-compatible client, Profile URL check, queue states, retention rules.

Tests: Swift Testing on `StenoCore`, TDD. Capture and transcription are verified by hand with test Recordings saved as fixtures. Automated runs of the app (DEBUG builds) refuse to start unless isolated with `-vaultPath`, `-testSummaryBaseURL` and `-dataDirectory`.

## Phases

Every phase closes with a concrete check.

| # | Phase | Done when |
|---|---|---|
| 0 | Xcode project + `StenoCore`, signing, Info.plist, `MenuBarExtra` with Start/Stop | The app starts in the menu bar and asks for permissions only once |
| 1 | **Capture** of the two Tracks in Segments, echo cancellation | A 12-minute Meet/Teams call produces 3+3 audible Segments, with Me free of the others' echo |
| 2 | **Local transcription** in Segments + Me/Others merge | The test call's Transcript file is readable, ordered and attributed |
| 3 | **Vault**: Meeting note, Managed section, frontmatter, `steno_id` (renaming moved to phase 4, with the title) | Tests green; the note appears in Obsidian at start and Personal notes stay intact after Processing |
| 4 | **Summary**: Settings window, Profiles, Keychain, OpenAI-compatible client, Templates, chunking, title and rename | Correct Summary of the test call with a remote Provider (in development OpenRouter, test recordings only). Still to try when the user sets them up: a local server (llama.cpp) and an EU Provider |
| 5 | **Full flow**: persistent queue, Regeneration, Retry, notifications, shortcut, retention | Two consecutive Meetings processed in the queue; Retry after stopping the local server |
| ~~6~~ | ~~Stop on silence~~ | Dropped: the user prefers to always stop by hand |

## Known risks

- **Ducking**: with voice processing active and `voiceProcessingOtherAudioDuckingConfiguration` at minimum, the Others Track records at about half volume. In a real Meet call (phase 1) the user did not notice any lowering of what they hear, so it only affects the recorded signal. If it ever bothers: echo cancellation off and headphones.
- **Local server context**: llama.cpp (`llama-server -c`), Ollama (`OLLAMA_CONTEXT_LENGTH`) and LM Studio have a small default context that cannot be changed per request through the OpenAI-compatible endpoint: it must be set when the server starts, consistent with the Profile's *max context* (minimum 8,192 tokens, Steno does not go below).
- **Truncated replies**: if the model stops at the length limit (`finish_reason: length`) the Summary counts as failed, not saved halfway. Very long Meetings merge partial summaries in groups until the final merge fits in the context.
- **Gaps in the audio**: a Segment's offset is computed from the frames written since the start of the Track. If a source drops buffers (device change, voice processing reset) the later offsets of that Track drift relative to the other. Phase 2: in the real 12-minute call the two Tracks end less than 10 ms apart, no visible drift in the Transcript. If it shows up (e.g. headphones plugged in mid-call), realign every Segment with the host time of its first buffer.
- **Words cut between Segments**: the 5-minute boundary can split a word. Phase 2: with 5-second Segments a sentence across two Segments comes back together correctly; in the real call no words were lost at the boundaries. If it matters, add a short overlap between Segments.
- **Whisper non-deterministic on degraded audio**: with temperature fallback, the same range can give different texts in two Processings. In the phase 2 test (voice picked up by a phone in another room, through Meet and played by the speakers) the first sentence was lost in one run out of three. Disabling the fallback makes the result stable but worse; Whisper's "no speech" threshold is disabled because it dropped exactly these ranges. To reassess if it happens with normal call audio.
- **Renaming with the note open in Obsidian**: Obsidian does not follow the rename: it closes the note and shows the previous one. Steno reads in `.obsidian/workspace.json` which note Obsidian shows. If, before the rename, it was the Meeting note, Steno waits 3 seconds for Obsidian to notice the rename and then, if Obsidian does not show the renamed note, opens it and checks again (up to 3 times). If Obsidian is not the frontmost app it waits (up to an hour) for the user to come back to it instead of bringing it forward. A note Steno opens meanwhile (a new Meeting, a notification) cancels the wait. If the user was looking at another note, nothing happens. Correctness over speed: the note may appear a few seconds after the notification.
- **Short Vocabulary terms and variants**: a variant is replaced everywhere it appears as a whole word, so a variant that is also a real word ("acne" for "Acme") would corrupt correct text; whoever writes the Vocabulary chooses the variants. Short terms that sound like common words ("Steno" next to "meno", "sono") are one more reason there is no engine biasing: the Summary prompt resolves them from context instead.
- **Whisper model download**: WhisperKit downloads the weights from Hugging Face. It is not Meeting data and does not affect ADR 0001, but it needs the network on first launch.
