# Steno v1 manual tests

Manual checks to run before using Steno for real meetings. Each one says what to do and what must happen. Labels are the English ones; on a Mac set to Italian the app shows the Italian translation (e.g. *Start meeting* = *Avvia riunione*).

Before starting: Steno running from the menu bar (waveform icon), Vault and a Summary Profile configured. **With a Profile outside the EU (e.g. OpenRouter) use test recordings only**: your own voice, public videos, never work meetings.

## 1. Recording

- [x] **Start from the menu**: *Start meeting* → the red dot appears in the bar, Obsidian opens `Meetings/<date> <time> - Meeting.md`.
- [x] **Duration**: open the menu while recording → first line "Recording · mm:ss".
- [x] **Shortcut**: ⌃⌥⌘R from another app starts, ⌃⌥⌘R again stops.
- [ ] **Template during the call**: change *Template* from the menu while recording → the Summary follows the last Template chosen.
- [ ] **Profile during the call**: the *Summary Profile* menu is hidden while recording (it is fixed at the start).

## 2. Processing

- [ ] **Notes Template**: the Summary has the topics in Meeting order, with bullets and sub-bullets, and *Next steps* at the end as a "What to do (Who)" checklist.
- [x] **Personal notes**: write a few lines under `## Personal notes` during the call → after the stop they are untouched and the Summary gives those topics priority.
- [ ] **Summary**: after the stop an hourglass in the bar, then the "Summary ready" notification; the note has the Summary, the Transcript link and the frontmatter (duration, language, template, provider).
- [x] **Title and rename**: the note is no longer "… - Meeting" but "… - <title>"; the Transcript in `Transcripts/` has the same name with "(transcript)". With the note open and Obsidian in front, Obsidian shows the renamed note, not the previous one.
- [ ] **Notification click**: opens the note in Obsidian.
- [x] **Note renamed by you**: rename the note during the call → Steno finds it and does not rename it.
- [x] **English meeting**: a test with an English video → Transcript and Summary in English.
- [ ] **Short first sentence**: say only "ok" or "sì" at the start, then talk for a minute → the first sentence is transcribed in the Meeting language, not translated.
- [ ] **Other Summary language**: a Template with `summary_language: fr` → Summary in French from an Italian meeting.

## 3. Queue and recent meetings

- [ ] **Two Meetings in a row**: stop the first one and start the second right away → the menu says "Processing… (1 more queued)", then two notifications.
- [ ] **Recent meetings → Open note**: opens the right note, even if you renamed or moved it.
- [x] **New Template**: Settings → *Templates* → type a name → *Create and open* → it opens in Obsidian; change instructions and sections and save.
- [ ] **Default Template**: choose the new Template as default → the next Meeting starts with it.
- [ ] **Delete Template**: *Delete* → confirm → the row disappears with no message, the file is in the Mac Trash; if it was the default, Notes is back. Notes has no *Delete*.
- [x] **Regenerate with Template**: *Recent meetings* → a Meeting → *Regenerate with Template* → your Template → the Summary changes, duration and Transcript do not.
- [ ] **Retry**: turn off the internet connection, record a short Meeting → "Processing failed" and ⚠️ in the note and in the menu; reconnect and *Retry* → Summary generated.

## 4. Edge cases

- [ ] **Microphone change**: during a Meeting connect or remove the AirPods, then keep talking → your sentences after the change are in the Transcript, at the right time compared with the others'.
- [ ] **Transcript only**: *Summary Profile* → *Transcript* (the Template menu disappears), record a Meeting → the note holds only the "Full transcript" link, no warning, notification "Transcript ready". In Recent meetings there is only *Regenerate with Profile*: choosing a Profile writes the Summary.
- [ ] **Quit during Processing**: stop a Meeting and quit Steno right away → at the next launch Processing resumes by itself.
- [x] **Italian interface**: `defaults write dev.mameli.steno AppleLanguages -array it`, restart Steno → menu, Settings and notifications in Italian (`defaults delete dev.mameli.steno AppleLanguages` to go back).
- [ ] **Wrong key**: in Settings replace the key with a random one → *Test connection* shows the provider's error; then put the right one back.

## 5. When you set them up

- [ ] **EU Provider** (e.g. Mistral): new Profile with key → *Test connection* → a test Meeting → *Regenerate with Profile* on an older Meeting to compare the Summaries.
- [ ] **Local server** (llama.cpp): new Profile without key, `http://localhost:8080/v1`, max context equal to the server's (`llama-server -c 32768`).

If something goes wrong: the ⚠️ message in the menu and in the note says why; copy it as it is.
