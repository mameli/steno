# Steno v1 manual tests

Manual checks to run before using Steno for real meetings. Each one says what to do and what must happen. Labels are the English ones; on a Mac set to Italian the app shows the Italian translation (e.g. *Start meeting* = *Avvia riunione*).

Before starting: Steno running from the menu bar (notebook icon), Vault and a Summary Profile configured. **With a Profile outside the EU (e.g. OpenRouter) use test recordings only**: your own voice, public videos, never work meetings.

## Icons

- [x] **App icon**: Finder and notifications show the orange notebook.
- [x] **Menu bar**: the notebook outline and handwriting are crisp on light and dark menu bars and when the menu is selected. Recording still shows a red dot; Processing still shows an hourglass.

- [ ] **Open at login**: Settings → *General* → *Open at login* on → Steno is in System Settings → General → Login Items; log out and back in → Steno is in the menu bar. Turn it off → it disappears from Login Items.

- [ ] **First use**: move `~/Library/Application Support/Steno/Models` to the Trash, start a Meeting → the menu shows "Downloading transcription model… N%" rising, then "Preparing transcription model, first time only", then nothing; the Meeting is transcribed. The menu does not blink while the percentage changes.

- [ ] **Parakeet**: with Models in the Trash, Settings → *Transcription* → *Download* on Parakeet v3 → percentage, then "Preparing…" while macOS compiles it, then *Use* and *Delete* appear. *Use* on Parakeet v3, record a Meeting with long and short replies → the Transcript is in the Meeting language, with sentences and times; note any reply in the wrong language.
- [ ] **Transcription models**: Settings → *Transcription* → *Download* on Small → percentage, then *Use* and *Delete* appear; *Download* on the model in use → the menu shows the percentage, and nothing once it is done; *Use* → "In use" moves to Small; a Meeting is transcribed with Small; *Retry* on an older Meeting with Large v3 Turbo in use transcribes it again with Large. *Delete* on Small brings back *Download*.

## 1. Recording

- [x] **Start from the menu**: *Start meeting* → the red dot appears in the bar, Obsidian opens `Meetings/<date> <time> - Meeting.md`.
- [x] **Duration**: open the menu while recording → first line "Recording · mm:ss".
- [x] **Shortcut**: ⌃⌥⌘R from another app starts, ⌃⌥⌘R again stops.
- [x] **Template during the call**: change *Template* from the menu while recording → the Summary follows the last Template chosen.
- [x] **Profile during the call**: the *Summary Profile* menu is hidden while recording (it is fixed at the start).

## 2. Processing

- [x] **Notes Template**: the Summary has the topics in Meeting order, with bullets and sub-bullets, and *Next steps* at the end as a "What to do (Who)" checklist.
- [x] **Personal notes**: write a few lines under `## Personal notes` during the call → after the stop they are untouched and the Summary gives those topics priority.
- [x] **Summary**: after the stop an hourglass in the bar, then the "Summary ready" notification; the note has the Summary, the Transcript link and the frontmatter (duration, language, template, provider).
- [x] **Title and rename**: the note is no longer "… - Meeting" but "… - <title>"; the Transcript in `Transcripts/` has the same name with "(transcript)". With the note open and Obsidian in front, Obsidian shows the renamed note, not the previous one.
- [x] **Notification click**: opens the note in Obsidian.
- [x] **Note renamed by you**: rename the note during the call → Steno finds it and does not rename it.
- [x] **English meeting**: a test with an English video → Transcript and Summary in English.
- [x] **Short first sentence**: say only "ok" or "sì" at the start, then talk for a minute → the first sentence is transcribed in the Meeting language, not translated.
- [x] **Other Summary language**: a Template with `summary_language: fr` → Summary in French from an Italian meeting.

## 3. Queue and recent meetings

- [x] **Two Meetings in a row**: stop the first one and start the second right away → the menu says "Processing… (1 more queued)", then two notifications.
- [x] **Recent meetings → Open note**: opens the right note, even if you renamed or moved it.
- [ ] **Meeting deleted from the Vault**: delete a Meeting note in Obsidian, open the menu → *Recent meetings* no longer lists it (an older Meeting takes its place); rename a note → the menu shows the new name.
- [x] **New Template**: Settings → *Templates* → type a name → *Create and open* → it opens in Obsidian; change instructions and sections and save.
- [x] **Default Template**: choose the new Template as default → the next Meeting starts with it.
- [x] **Delete Template**: *Delete* → confirm → the row disappears with no message, the file is in the Mac Trash; if it was the default, Notes is back. Notes has no *Delete*.
- [ ] **Retry with another Template**: choose another Template in the menu → *Recent meetings* → a Meeting → *Retry* → the Summary follows the new Template.
- [ ] **Retry without audio**: Settings → *Recordings* → *Delete audio* → *Retry* on a Meeting → the Summary is made again from the Transcript in the Vault, duration and Transcript do not change.
- [ ] **Deleted Profile**: start a Meeting with a Profile, delete that Profile in Settings before the Summary → the note says the Profile was deleted; choose another Profile and *Retry* → Summary written.
- [ ] **New Profile**: *Add Profile* → the menu still shows the Profile active before (or *Transcript*) until *Use for Summaries*.
- [ ] **Recordings in Settings**: the space used matches the folder opened by *Show in Finder*; *Delete audio* asks for confirmation and brings it to zero.
- [x] **Retry**: turn off the internet connection, record a short Meeting → "Processing failed" and ⚠️ in the note and in the menu; reconnect and *Retry* → Summary generated.

## Echo residue

- [ ] **Speakers without headphones**: a call on the Mac speakers where you mostly listen and reply now and then → the Transcript has your replies as Me, and no short English or nonsense Me sentences ("Oh yeah", "The five.") while the others talk.
- [ ] **Quiet reply**: say "sì" or "mm-hmm" softly while the others talk → it stays in the Transcript.

## Speakers

- [ ] **First use**: move `~/Library/Application Support/Steno/Models/fluidaudio/speaker-diarization` to the Trash, record a call with two or three other people → the Transcript has *Speaker 1*, *Speaker 2*… instead of *Others*, with the turns matching who spoke; the models are back in that folder.
- [ ] **Names in the Summary**: in a call where someone is called by name and answers → the Summary uses that name for their points and actions; for someone never named it writes "Speaker N" only as who takes on an action, never in a heading or in the other bullets.
- [ ] **Offline**: with the diarization models deleted and no internet, *Retry* on a Meeting with its audio → the Transcript has *Others*, the menu and the notification say "Speakers not told apart: …", the Summary is written anyway.
- [ ] **Old Transcript**: *Retry* without audio on a Meeting processed before Speakers existed → the Summary is made from the Transcript with *Others*.

## Vocabulary

- [ ] **Open Vocabulary**: Settings → *Vocabulary* → *Open Vocabulary* → `Meetings/_Vocabulary.md` is created with the explanation text and opens in Obsidian; *Entries* says 0. Add `- Scaleway = scale uai | our EU cloud provider`, go back to the Settings window → *Entries* says 1.
- [ ] **Variants in the Transcript**: add a term with a variant Parakeet really gets wrong in your voice, record a short Meeting saying it → in the Transcript file the term is written right; the Meeting note's Summary writes it right too.
- [ ] **Terms in the Summary**: say a term that is in the Vocabulary but write no variant for it, with recognition getting it wrong → the Summary spells the term right when the context makes it clear, and leaves other doubtful words alone.
- [ ] **Short terms**: a term that sounds like common words (like "Steno" next to "meno", "sono") → ordinary sentences with "meno" or "sono" are not changed, in the Transcript or in the Summary.
- [ ] **Retry with a new variant**: add a variant for a word that is wrong in an older Meeting still having its audio → *Retry* → the Transcript file has the term. Without the audio, *Retry* does not touch the Transcript text.
- [ ] **Transcript only**: *Summary Profile* → *Transcript*, record a Meeting saying a word that has a variant → the variant is replaced in the Transcript even with no Summary.
- [ ] **No Vocabulary file**: delete `_Vocabulary.md` → Meetings are processed as before, *Entries* says 0.

## 4. Edge cases

- [x] **AirPods from the start**: AirPods connected before starting, not in a call → the Me Track records (there is a `me-000.m4a`), even though macOS switches them to call mode.
- [ ] **Microphone change**: during a Meeting connect or remove the AirPods, then keep talking → your sentences after the change are in the Transcript, at the right time compared with the others'.
- [x] **Transcript only**: *Summary Profile* → *Transcript* (the Template menu disappears), record a Meeting → the note holds only the "Full transcript" link, no warning, notification "Transcript ready". Then choose a Profile in the menu and *Retry* → the Summary is written.
- [x] **Quit during Processing**: stop a Meeting and quit Steno right away → at the next launch Processing resumes by itself.
- [x] **Italian interface**: `defaults write dev.mameli.steno AppleLanguages -array it`, restart Steno → menu, Settings and notifications in Italian (`defaults delete dev.mameli.steno AppleLanguages` to go back).
- [x] **Wrong key**: in Settings replace the key with a random one → *Test connection* shows the provider's error; then put the right one back.

## 5. When you set them up

- [ ] **EU Provider** (e.g. Mistral): new Profile with key → *Test connection* → a test Meeting → choose it in the menu and *Retry* on an older Meeting to compare the Summaries.
- [x] **Local server** (llama.cpp): new Profile without key, `http://localhost:8080/v1`, max context equal to the server's (`llama-server -c 32768`).

If something goes wrong: the ⚠️ message in the menu and in the note says why; copy it as it is.
