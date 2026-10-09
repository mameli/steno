



<p align="center">
  <img src="Takku/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" alt="Takku icon" width="128">
</p>

<h1 align="center">Takku</h1>

<p align="center"><a href="https://github.com/mameli/takku/releases/latest"><b>Download the latest version</b></a> · macOS 15+ · Apple Silicon</p>

A macOS menu bar app that records your meetings, transcribes them **on your Mac** and writes the Transcript and a Summary into your **Obsidian** vault. You choose who writes the Summary: a model running locally, or any OpenAI-compatible provider you trust (for example one hosted in the EU).

It was built as an alternative to Granola for people whose company does not allow meeting audio and text to leave the EU.

- **Records both sides of a call**: your microphone and the system audio (Meet, Zoom, Teams, any app), with echo cancellation.
- **Tells the others apart**: the Transcript shows Speaker 1, Speaker 2… by voice, and the Summary names them when the call makes clear who they are, or when you name them in the note.
- **Knows your calendar** (optional): the note takes the name and the participants of the event in progress.
- **Suggests when to record**: a notification when a call app takes the microphone, and another when the call seems over.
- **Transcribes locally** with OpenAI Whisper or NVIDIA Parakeet: the audio never leaves the Mac. Choose between Whisper Large v3 Turbo (default), its full version, Small and Parakeet v3 in *Settings → Transcription*.
- **Summarises with a provider you pick**: llama.cpp, Ollama or LM Studio on your Mac, or a remote OpenAI-compatible API. You can also skip the Summary and keep only the Transcript.
- **Writes Markdown into Obsidian**: one note per meeting, opened when the meeting starts so you can take notes, plus a separate Transcript file. Your own notes are kept and used to steer the Summary.
- **Templates are notes in your vault**: write the structure and instructions of the Summary in Obsidian.
- **A Vocabulary for your jargon**: names and technical terms that recognition gets wrong are fixed in the Transcript and spelled right in the Summary.

https://github.com/user-attachments/assets/f26da8d8-59b4-490a-af40-25801e35b958

## Requirements

- A Mac with Apple Silicon and macOS 15 or later
- An Obsidian vault (any folder works, Obsidian is only needed to open the notes)
- Disk space for the transcription model, downloaded on first use: about 650 MB for the default one (from 220 MB to 1.6 GB depending on the model)

Meetings can be in Italian, English or 23 other European languages (*Settings → Transcription → Meeting languages*), one language per meeting; the Summary can be written in any language.

## Install

1. Install it with [Homebrew](https://brew.sh):
   ```sh
   brew install --cask mameli/takku/takku
   ```
   Or without Homebrew: download `Takku-<version>.zip` from the [latest release](https://github.com/mameli/takku/releases/latest) (Safari unzips it on its own) and move **Takku** to **Applications**.
2. Open Takku. macOS says it cannot verify the app: Takku is signed, but not notarized by Apple, which needs a paid developer account. Press **Done**.
3. Go to **System Settings → Privacy & Security**, scroll down and press **Open Anyway** next to Takku, then confirm with your password. Alternatively, run `xattr -dr com.apple.quarantine /Applications/Takku.app` in Terminal before opening it.

Takku appears in the menu bar, not in the Dock. Continue with [First setup](#first-setup).

**Updating**: `brew upgrade --cask takku`, or quit Takku and replace it in Applications with the new version; then repeat steps 2 and 3. Settings, Profiles, API keys, permissions and downloaded models are kept. `brew uninstall --cask --zap takku` also deletes Takku's settings, Recordings and models; your vault is not touched.

**Coming from Steno**: Takku is Steno's new name (from *taccuino*, the notebook in its icon). `brew upgrade` replaces Steno with Takku; without Homebrew, install Takku as above and delete Steno from Applications. At the first launch Takku brings over Steno's settings, Profiles, Recordings and models; macOS asks once for your password to let Takku read the API keys saved by Steno (choose *Always Allow*). The permissions (microphone, system audio, calendars, notifications) and *Open at login* must be granted again. Notes already in your vault keep working.

On Macs managed by your company, IT may not allow apps that are not notarized. To build Takku yourself instead, see [Build from source](#build-from-source).

## First setup

1. **Permissions.** On the first meeting macOS asks for the microphone and for *System Audio Recording Only*: allow both.
   During that first meeting Takku also downloads the transcription model and prepares it, which takes a few minutes once: the menu shows the progress, and the first Summary waits for it.
2. **Vault.** Takku menu → *Settings…* → *Obsidian Vault* → choose your vault folder. Takku creates `Meetings/_Templates/` with a default *Notes* Template; `Meetings/` and `Meetings/Transcripts/` fill up with the first meeting.
3. **Open at login** (optional). *Settings → General*: Takku starts with the Mac, in the menu bar. Turn it on from the copy in `/Applications`, the one you will keep using.
4. **Summary Profile.** In *Summary Profiles* add a Profile: name, base URL, model, max context and, if the provider needs one, the API key (stored in the macOS Keychain). Press *Test connection*. Some examples:

   | Provider | Base URL | Model | Key |
   |---|---|---|---|
   | llama.cpp on your Mac (`llama-server -hf ggml-org/gemma-4-E4B-it-GGUF:Q4_0 -c 32768`) | `http://localhost:8080/v1` | `ggml-org/gemma-4-E4B-it-GGUF:Q4_0` | none |
   | [Regolo.ai](https://regolo.ai) (Italy) | `https://api.regolo.ai/v1` | `gemma4-31b` | yes |
   | [Mistral](https://console.mistral.ai) (France) | `https://api.mistral.ai/v1` | `mistral-medium-latest` | yes |

   Set *max context* to the model's real limit (for a local server, the `-c` it was started with). Plain `http://` is accepted only for servers on your Mac.

   Takku does not check where a provider processes your data: check the provider's terms, and your company's policy, before using it for real meetings.

## Use

- **Start and stop** a meeting from the menu bar or with **⌃⌥⌘R** from any app. While recording the icon is a red dot and the menu shows the duration. If a call app keeps the microphone for 15 seconds, a notification offers to start; when it lets the microphone go, another offers to stop (*Settings → General* to turn them off).
- **Mark a moment** with **⌃⌥⌘M** while recording: the dot turns into a star for a second, the passage gets a ⭐ in the Transcript and the Summary gives it priority.
- If Takku hears nothing from the microphone or from the call for 2 minutes, the menu says so; if it has heard nothing since the start, a notification tells you what to check.
- The meeting note opens in Obsidian: write your own notes under **Personal notes**. Takku never touches them.
- After the stop Takku finishes the transcription, writes the Summary at the top of the note, links the Transcript and renames the note with a short title (unless it is named after a calendar event). A notification tells you when it is ready.
- **Template** and **Summary Profile** are chosen in the menu. Choose *Transcript* as Profile to get only the Transcript, with no Summary.
- **Recent meetings → Retry** redoes a meeting with the Template and Profile currently selected: use it after an error, or to get a Summary with another Template. *Show all in Obsidian…* lists every meeting note.

### Calendar

Turn on *Settings → General → Use the calendar* and allow access: when a meeting starts during an event, the note is named after it and lists who was invited in `participants`. The list helps the Summary name the Speakers; correct it in the note if it is wrong, it counts on the next Retry.

### Speaker names

If the Summary cannot tell who a Speaker is, read the Transcript and say it in the note's frontmatter, then *Retry*:

```yaml
speakers:
  - Speaker 1 = Mario Rossi
  - Speaker 3 = Anna Bianchi
```

The Transcript then shows *Mario Rossi (Speaker 1)* and the Summary uses the name.

### Templates

A Template is a note in `Meetings/_Templates/`: its text tells the model what to write and how. Create one from *Settings → Templates*, then edit it in Obsidian. Add `summary_language: en` (or `it`, `fr`, …) to its frontmatter to always get the Summary in that language; otherwise it follows the language of the meeting.

### Vocabulary

Names, acronyms and technical words that recognition gets wrong go in `Meetings/_Vocabulary.md`: open it from *Settings → Vocabulary*. One entry per line: the correct term, then after `=` what is usually heard instead, then after `|` a short description, the last two optional:

```markdown
- Kubernetes = cubernetes, kubernetis
- dbt = di bi ti | data transformation tool
- Holacracy
```

The variants are replaced with the term in the Transcript, as whole words: do not list a variant that is also an ordinary word, or it is replaced everywhere. All the terms are passed to the model, which spells them right in the Summary when the context makes it clear. Changes count from the next meeting, or from a Retry while the audio of that meeting is kept.

### Where your data is

- **Notes, Transcripts, Templates and Vocabulary**: in your vault, as plain Markdown.
- **Audio**: in `~/Library/Application Support/Takku/Recordings/`, about 20 MB per hour of meeting. It is deleted after 7 days (*Settings → Recordings*); after that, Retry rebuilds the Summary from the Transcript in the vault.
- **API keys**: in the macOS Keychain.
- **Transcription model**: in `~/Library/Application Support/Takku/Models/`, downloaded once from Hugging Face. Only the model is downloaded; no audio or text is sent.
- **Calendar**: read on the Mac through macOS, only if you turn it on; titles and participants go into the note, and the participants into the Summary request.
- **Update check**: once a day Takku asks GitHub for the latest version (*Settings → General → Check for updates*). The request carries nothing about you or your meetings.

Recording a meeting may require the consent of the other participants: tell them, and follow the rules that apply to you.

## Development

### Build from source

1. Install Xcode 16 or later from the App Store and open it once.
2. Clone the repository:
   ```sh
   git clone https://github.com/mameli/takku.git
   cd takku
   ```
3. Choose how to sign it (see [Signing](#signing)) and copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`.
4. Build and copy it to Applications:
   ```sh
   xcodebuild -project Takku.xcodeproj -scheme Takku -configuration Release -derivedDataPath build/DerivedData build
   cp -R build/DerivedData/Build/Products/Release/Takku.app /Applications/
   open /Applications/Takku.app
   ```

### Signing

macOS ties the microphone and system audio permissions to the app's signature: with a stable signature they are asked once, otherwise again after every build. Two free options:

- **A self-signed certificate.** Keychain Access → Certificate Assistant → Create a Certificate…: name `Takku`, Identity Type *Self-Signed Root*, Certificate Type *Code Signing*; tick *Let me override defaults* and set a validity of 3650 days. Then double-click the certificate, and under *Trust* set *Code Signing* to *Always Trust*. The first build asks to use the key: choose *Always Allow*.
- **Your Apple ID's free Personal Team.** Add your Apple ID in Xcode → Settings → Accounts, then in `Config/Local.xcconfig` use the second option with your Team ID.

Without `Config/Local.xcconfig` the app is signed ad hoc and the permissions are asked again after every build.

### Working on the code

```sh
xcodebuild -project Takku.xcodeproj -scheme Takku -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Takku.app
cd TakkuCore && swift test   # domain logic tests
```

- `Takku/` is the app (capture, transcription, Vault, Settings, menu); `TakkuCore/` is a Swift package with the domain logic and its tests, without AppKit or AVFoundation.
- [docs/SPEC.md](docs/SPEC.md) describes how everything works, [CONTEXT.md](CONTEXT.md) is the glossary, [docs/adr](docs/adr/) records the main decisions, and [docs/TESTING.md](docs/TESTING.md) lists the checks to run by hand.
- User-facing strings are written in English in the code and translated in `Takku/Localizable.xcstrings` (Italian). Error messages raised in `TakkuCore` are looked up in the app's catalog too and must be added to it by hand. To try the Italian interface: `defaults write app.takku.takku AppleLanguages -array it`.
- `scripts/release.sh` builds a Release signed with the `Takku` certificate, zips it, publishes it as a GitHub Release tagged with `MARKETING_VERSION` from `Config/Base.xcconfig` and updates the cask in the Homebrew tap ([mameli/homebrew-takku](https://github.com/mameli/homebrew-takku), cloned next to this repository). Every release needs a new version: a published one is never replaced, because Homebrew checks the zip's SHA-256. `--dry-run` stops after the zip.
- Debug builds accept launch arguments for automated tests (`-smokeTestSeconds`, `-transcribeRecording`, …): see `runSmokeTestIfRequested()` in `Takku/MeetingController.swift`. They refuse to run unless pointed at a test vault, a test data folder and a test Summary server.

## License

MIT, see [LICENSE](LICENSE).

Takku downloads and runs third-party models: OpenAI Whisper through [WhisperKit](https://github.com/argmaxinc/WhisperKit) (MIT), and [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) (CC BY 4.0) converted by FluidInference and run through [FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache 2.0).
