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
- Recording kept for 7 days, **Processing** queue
- English user interface with Italian translation (string catalogs); English Vault format

**Out of v1** (most likely first)
1. Calendar (title and participants from EventKit)
2. Remote transcription (local is enough: 12 minutes in 50 seconds on an M3 Pro); Profiles will then also get the transcription Role
3. Room capture mode (microphone only, for in-person meetings)
4. "Looks like a call" notification when an app grabs the microphone
5. Real diarization (Person 1, 2…)
6. Ready-made Provider presets
7. Distribution to others (Developer ID signing, notarization)
8. Automatic stop on silence at the end of the call (was phase 6)

## Main flow

1. **Start** (click or shortcut). Steno:
   - creates the Meeting identifier and the Recording folder;
   - creates the Meeting note `<Vault>/Meetings/2026-10-04 1430 - Meeting.md` (see [structure](#meeting-note));
   - opens it in Obsidian with `obsidian://open?path=<absolute path>`;
   - starts capturing the two Tracks.
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
- **Me**: `AVAudioEngine` on the default microphone with `setVoiceProcessingEnabled(true)` for echo cancellation. With voice processing the microphone delivers 9 channels: only channel 0, already cleaned, is kept. The engine's output branch must not be connected, otherwise the start fails (-10875). Can be disabled with `defaults write dev.mameli.steno echoCancellation -bool false`. Requires `NSMicrophoneUsageDescription`. If the default microphone changes during a Meeting (AirPods connected or removed) the engine stops: Steno starts a new one on the new default microphone (at most 5 times a minute) and the hole, usually a second or two, is filled with silence so the Track stays aligned with Others. Any hole over half a second in a Track is filled the same way.
- Each Track is written in **5-minute Segments** (`me-000.m4a`, `others-000.m4a`, …), AAC mono 16 kHz. Reasons: a crash loses at most one Segment; closed Segments are transcribed during the call; files stay under remote Providers' upload limits.
- The two Tracks share the start clock: every Segment records its offset from the start of the Meeting. Each Track's Segment list (`me-segments.json`, `others-segments.json`) is updated whenever a Segment opens, so offsets survive a crash; at the stop it goes into `recording.json`, which is written even if a Track was interrupted.

**Stop on silence**: out of v1 by the user's choice (the Meeting is always stopped by hand, from the menu or with ⌃⌥⌘R).

## Transcription

- Each Track is transcribed separately. The Utterances of the two Tracks are sorted by start time and merged into paragraphs (rules below).
- A Segment that cannot be transcribed does not block the others: the Transcript is written with a gap and the error is reported.
- Whisper only gets the **speech ranges** of each Segment: half-second windows with RMS above 0.004, pauses under 2 seconds absorbed, a quarter of a second of margin on each side. On silence, echo residue and distant voices Whisper makes up sentences ("Grazie.", dozens of times in the phase 1 test). Annotations such as `[BLANK_AUDIO]` or sentences in parentheses are dropped anyway. A speech range of at most 3 seconds whose whole text is a stock subtitle sentence ("Grazie.", "Thank you.", "Sottotitoli creati dalla comunità Amara.org"…) is dropped too: it is Whisper's reaction to a short noise such as a notification sound. A real isolated "Grazie." from the others is lost with it.
- A Transcript paragraph joins consecutive Utterances of the same Track, but breaks after a pause longer than 30 seconds or when an Utterance starts more than 60 seconds after the paragraph's start: a new timestamp about every minute (a Whisper Utterance is at most 30 seconds long).
- The result of each Segment (language and Utterances) is saved next to the audio (`me-000.m4a.json`), so a new Processing does not transcribe again what is done.
- **Local**: WhisperKit, model `openai_whisper-large-v3-v20240930_turbo_632MB` (646 MB), downloaded on first use to `~/Library/Application Support/Steno/Models` and prepared while the first Meeting is in progress.
- **Language**: `auto` or forced `it`/`en` (`defaults write dev.mameli.steno language it`). Detection runs on up to 30 seconds of speech only (the voice ranges, no silence) of the first Segment that has any, from either Track, picking only between Italian and English, and holds for the whole Meeting. It is locked only when there are at least 10 seconds of speech: on a short "ok" Whisper can pick the wrong language and then *translate* instead of transcribing. With less speech the detected language is provisional: it applies to that Segment only, detection is tried again on the next one, and at the end of Processing the Segments transcribed with a provisional language different from the locked one are transcribed again. If the language is never locked (very little speech in the whole Meeting) the provisional results stay. Detecting on the first 30 seconds of audio is not enough: in the real phase 1 test the Me Track started with 80 seconds of near silence and Whisper classified it as Swedish. The language used is saved in every Segment's cache; if a different language is forced later, the Segment is transcribed again.
- **Remote** (after v1): `POST {baseURL}/audio/transcriptions` (multipart, one Segment per request) through the OpenAI-compatible adapter. Only at the stop: during the call the audio never leaves the Mac.

File `<Vault>/Meetings/Transcripts/2026-10-04 1430 - <Title> (transcript).md` (a copy without frontmatter stays in `transcript.md` in the Recording folder while the audio is there). A new Processing of the same Meeting overwrites the existing file, found through `steno_id`:

```markdown
---
steno_id: 6F1C…
meeting: "[[2026-10-04 1430 - Title]]"
language: it
---
**[00:00] Others:** Buongiorno a tutti, partiamo dal…

**[00:42] Me:** Sì, sul primo punto…
```

## Meeting note

```markdown
---
steno_id: 6F1C…
date: 2026-10-04T14:30
duration: 47m
template: Notes
language: it
transcription_provider: Local
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
- Steno rewrites **only** the text between `%% steno:start %%` and `%% steno:end %%` and **its own** frontmatter keys (`duration`, `language`, `transcription_provider`, `summary_provider`, `template`, `transcript`). Keys added by the user stay. `date` and `tags` are written only at creation: from then on they belong to the user. `steno_id` is restored at every update if the user deleted it, otherwise the note could not be found again.
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
- In Settings, Templates section: list, default Template, "New Template" (name → file created from Notes and opened in Obsidian), "Open in Obsidian", "Delete" (moves the file to the Trash, with no message: the row disappearing is enough; if it was the default, Notes becomes the default again; Notes itself cannot be deleted). New files (Templates, Meeting notes) are opened in Obsidian after a second, otherwise Obsidian may not have noticed them yet and answers "file not found". The text is written in Obsidian: Steno has no editor.

## Summary

- `POST {baseURL}/chat/completions` with:
  - **fixed system prompt** (in English): write the summary in the language stated explicitly ("Write the summary in Italian", whatever language the Template is written in), follow the Template's structure and instructions, do not invent, attribute to Me/Others, actions as a checklist in the Template's format (otherwise `- [ ] who: what (when)`), give priority to the topics of the Personal notes;
  - **user message**: Template, Personal notes, Transcript.
- **Summary language**: the Template's `summary_language` (any language), otherwise the Meeting's detected language, otherwise (no speech, or detection failed) Italian.
- **Title**: a second short call on the Summary ("at most 6 words, no date", in the Summary language), cleaned of headings, "Title:" prefixes, quotes, bold and final punctuation. If no title comes back the note keeps its provisional name: it is not an error.
- **Managed section**: the Summary followed by `Full transcript: [[…]]`. With *Transcript* chosen as Summary Profile it holds only the `Full transcript: [[…]]` link, with no warning, and the note keeps its provisional name. If the Summary fails (Provider error, Meeting without speech) it shows `⚠️ Summary not generated: <reason>` and the Transcript link, which stays usable. Managed section markers in the model's reply are removed.
- **Token estimate**: about 3 characters per token, with 4,096 tokens reserved for the reply; a block never splits a Transcript paragraph.
- **Long Meetings**: every Summary Profile has a *max context* field. If Transcript + notes + Template exceed it, the Transcript is split into blocks, every block is summarised and the partial summaries are merged with the Template (in groups, if even the merge does not fit).
- **Regeneration**: from "Recent meetings" → *Regenerate with* ▸ Template / Profile. Reads the current Transcript and Personal notes again and rewrites only the Managed section. It is available even after 7 days, because the Transcript is in the Vault.

## Profiles and settings

**Profile** (v1: Summary only): name, base URL, API key (in the Keychain, optional for local servers), model, max context. Examples: "Local llama.cpp" (`http://localhost:8080/v1`), "Mistral EU" (`https://api.mistral.ai/v1`). Transcription is always local (WhisperKit). A Profile outside the EU (e.g. OpenRouter) is allowed only for development with test recordings: Steno does not prevent it, the choice stays with the user (exception recorded in ADR 0001). The Profile is fixed when the Meeting starts. The URL must be `https://`; `http://` is allowed only for servers on this Mac (`localhost`, `127.0.0.1`, `*.local`).

**Settings** (UserDefaults; secrets in the Keychain). In the v1 Settings window:
- Vault path
- Templates and default Template
- Summary Profiles and active Profile (with "Test connection")

For now from the terminal only (`defaults write dev.mameli.steno …`), to move into the Settings window when they are needed:
- language (`auto` | `it` | `en`)
- echo cancellation on/off
- audio retention days (`retentionDays`, default 7)

The global shortcut is fixed: ⌃⌥⌘R. If another app already uses it, the menu says so.

The folders are fixed: `Meetings/`, `Meetings/Transcripts/`, `Meetings/_Templates/`. The Italian format of earlier development versions is not supported: those notes and Recordings were deleted.

## Menu bar

- **Idle**: Start meeting (shortcut) · Template ▸ (hidden when the Summary Profile is *Transcript*) · Summary Profile ▸ (*Transcript* or a Profile) · Recent meetings ▸ (Open note · Regenerate with ▸ · Retry) · Settings… · Quit
- **Recording**: only a red dot in the bar; in the menu "Recording · duration" · Stop · Template ▸ · Settings…
- **Processing**: hourglass in the bar; in the menu "Processing… (N more queued)"

The interface is in English in the code and translated to Italian in `Steno/Localizable.xcstrings` and `Steno/InfoPlist.xcstrings`: macOS picks the language of the system. Error messages from `StenoCore` are looked up in the app's catalog too. The structure Steno writes into the Vault (headings, markers, keys, labels, status lines such as "Summary not generated:") is always in English; the error detail after it follows the app language, like the menu.

## State and retention

- `~/Library/Application Support/Steno/Recordings/<steno_id>/`: audio Segments, per-Segment transcription cache (language, whether it was reliable, Utterances), `recording.json` (start, end, Segments) and `processing.json` (status: recording, queued, processing, regenerating, completed, failed with reason; Template; Profile fixed at start; note path).
- Persistent Processing queue, one Meeting at a time: at app restart queued or in-progress Processing resumes, oldest first. A Recording interrupted by a crash is rebuilt from the Segment lists and queued: only the Segment open at the crash is lost (an unclosed AAC file is unreadable).
- An unreadable Segment is a warning ("Incomplete transcript"), not a failure: the Summary is generated with what there is.
- At app launch and every day: deletion of the audio (and transcription caches) of Meetings older than 7 days that are processed or failed, never of those recording, queued, processing or regenerating. `recording.json` and `processing.json` stay: the Meeting stays among the recent ones and can be Regenerated.
- **Notifications**: "Summary ready" (click → note in Obsidian) or "Processing failed" with the reason.
- **Global shortcut** ⌃⌥⌘R: starts or stops the Meeting from any app.
- **Recent meetings** (the last 5): Open note · Retry (while the audio is there: redoes the whole Processing, Segments already transcribed come from the cache) · Regenerate with Template ▸ (not for a Meeting recorded with *Transcript*) / with Profile ▸ (Summary only, from the Transcript in the Vault; does not rename the note and does not change the Meeting's saved Template and Profile, which Retry keeps using). Retry and Regenerate appear only for concluded Meetings (completed or failed), never for one recording or queued. A Regeneration interrupted by a restart is not repeated: the Meeting goes back to completed with the previous Summary.
- Without a configured Vault Processing stops at the Transcript and the notification says "Transcript ready", not "Summary ready".

## Project structure

- **Xcode app** `Steno` (SwiftUI, `MenuBarExtra`, macOS 15 target, Personal Team signing): audio capture, WhisperKit, notifications, shortcut, Keychain, UI.
- **Local Swift package** `StenoCore`, testable with `swift test` and without AppKit or AVFoundation: Segments → Transcript merging, reading and writing the Meeting note (Managed section, frontmatter, lookup by `steno_id`), Template parsing, prompt building and chunking, OpenAI-compatible client, Meeting/queue state machine, retention rules.

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
- **Renaming with the note open in Obsidian**: Obsidian does not follow the rename: it closes the note and shows the previous one. If Obsidian is the frontmost app, Steno opens the renamed note again; otherwise it does not bring Obsidian forward and the notification opens the note. Fallback if this is not enough: do not rename (title only in the heading).
- **Whisper model download**: WhisperKit downloads the weights from Hugging Face. It is not Meeting data and does not affect ADR 0001, but it needs the network on first launch.
