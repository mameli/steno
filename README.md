<p align="center">
  <img src="Steno/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" alt="Steno icon" width="128">
</p>

<h1 align="center">Steno</h1>

A macOS menu bar app that records your meetings, transcribes them **on your Mac** and writes the Transcript and a Summary into your **Obsidian** vault. You choose who writes the Summary: a model running locally, or any OpenAI-compatible provider you trust (for example one hosted in the EU).

It was built as an alternative to Granola for people whose company does not allow meeting audio and text to leave the EU.

- **Records both sides of a call**: your microphone and the system audio (Meet, Zoom, Teams, any app), with echo cancellation.
- **Transcribes locally** with Whisper ([WhisperKit](https://github.com/argmaxinc/WhisperKit)): the audio never leaves the Mac.
- **Summarises with a provider you pick**: llama.cpp, Ollama or LM Studio on your Mac, or a remote OpenAI-compatible API. You can also skip the Summary and keep only the Transcript.
- **Writes Markdown into Obsidian**: one note per meeting, opened when the meeting starts so you can take notes, plus a separate Transcript file. Your own notes are kept and used to steer the Summary.
- **Templates are notes in your vault**: write the structure and instructions of the Summary in Obsidian.

## Requirements

- A Mac with Apple Silicon and macOS 15 or later
- Xcode 16 or later, to build it (see [Install](#install))
- An Obsidian vault (any folder works, Obsidian is only needed to open the notes)
- About 650 MB of disk for the transcription model, downloaded on first use

Meetings can be in Italian or English, one language per meeting; the Summary can be written in any language.

## Install

Steno is not signed with a paid Apple Developer ID, so there is no ready-made download: you build it yourself with a free Apple account. It takes a few minutes.

1. Install Xcode from the App Store and open it once.
2. In Xcode → Settings → Accounts, add your Apple ID. This creates a free *Personal Team*.
3. Clone the repository and set your Team ID (Xcode → Settings → Accounts → your team; or [developer.apple.com/account](https://developer.apple.com/account) → Membership):
   ```sh
   git clone https://github.com/mameli/steno.git
   cd steno
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   # edit Config/Local.xcconfig and replace XXXXXXXXXX with your Team ID
   ```
4. Build and copy it to Applications:
   ```sh
   xcodebuild -project Steno.xcodeproj -scheme Steno -configuration Release -derivedDataPath build/DerivedData build
   cp -R build/DerivedData/Build/Products/Release/Steno.app /Applications/
   open /Applications/Steno.app
   ```

Without your Team ID the app is signed ad hoc and macOS asks for the microphone and audio permissions again after every build.

## First setup

1. **Permissions.** On the first meeting macOS asks for the microphone and for *System Audio Recording Only*: allow both.
2. **Vault.** Steno menu → *Settings…* → *Obsidian Vault* → choose your vault folder. Steno creates `Meetings/_Templates/` with a default *Notes* Template; `Meetings/` and `Meetings/Transcripts/` fill up with the first meeting.
3. **Open at login** (optional). *Settings → General*: Steno starts with the Mac, in the menu bar. Turn it on from the copy in `/Applications`, the one you will keep using.
4. **Summary Profile.** In *Summary Profiles* add a Profile: name, base URL, model, max context and, if the provider needs one, the API key (stored in the macOS Keychain). Press *Test connection*. Some examples:

   | Provider | Base URL | Model | Key |
   |---|---|---|---|
   | llama.cpp on your Mac (`llama-server -hf ggml-org/gemma-4-E4B-it-GGUF:Q4_0 -c 32768`) | `http://localhost:8080/v1` | `ggml-org/gemma-4-E4B-it-GGUF:Q4_0` | none |
   | [Regolo.ai](https://regolo.ai) (Italy) | `https://api.regolo.ai/v1` | `gemma4-31b` | yes |
   | [Mistral](https://console.mistral.ai) (France) | `https://api.mistral.ai/v1` | `mistral-medium-latest` | yes |

   Set *max context* to the model's real limit (for a local server, the `-c` it was started with). Plain `http://` is accepted only for servers on your Mac.

   Steno does not check where a provider processes your data: check the provider's terms, and your company's policy, before using it for real meetings.

## Use

- **Start and stop** a meeting from the menu bar or with **⌃⌥⌘R** from any app. While recording the icon is a red dot and the menu shows the duration.
- The meeting note opens in Obsidian: write your own notes under **Personal notes**. Steno never touches them.
- After the stop Steno finishes the transcription, writes the Summary at the top of the note, links the Transcript and renames the note with a short title. A notification tells you when it is ready.
- **Template** and **Summary Profile** are chosen in the menu. Choose *Transcript* as Profile to get only the Transcript, with no Summary.
- **Recent meetings → Retry** redoes a meeting with the Template and Profile currently selected: use it after an error, or to get a Summary with another Template.

### Templates

A Template is a note in `Meetings/_Templates/`: its text tells the model what to write and how. Create one from *Settings → Templates*, then edit it in Obsidian. Add `summary_language: en` (or `it`, `fr`, …) to its frontmatter to always get the Summary in that language; otherwise it follows the language of the meeting.

### Where your data is

- **Notes and Transcripts**: in your vault, as plain Markdown.
- **Audio**: in `~/Library/Application Support/Steno/Recordings/`, about 20 MB per hour of meeting. It is deleted after 7 days (*Settings → Recordings*); after that, Retry rebuilds the Summary from the Transcript in the vault.
- **API keys**: in the macOS Keychain.
- **Transcription model**: in `~/Library/Application Support/Steno/Models/`, downloaded once from Hugging Face. Only the model is downloaded; no audio or text is sent.

Recording a meeting may require the consent of the other participants: tell them, and follow the rules that apply to you.

## Development

```sh
xcodebuild -project Steno.xcodeproj -scheme Steno -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Steno.app
cd StenoCore && swift test   # domain logic tests
```

- `Steno/` is the app (capture, transcription, Vault, Settings, menu); `StenoCore/` is a Swift package with the domain logic and its tests, without AppKit or AVFoundation.
- [docs/SPEC.md](docs/SPEC.md) describes how everything works, [CONTEXT.md](CONTEXT.md) is the glossary, [docs/adr](docs/adr/) records the main decisions, and [docs/TESTING.md](docs/TESTING.md) lists the checks to run by hand.
- User-facing strings are written in English in the code and translated in `Steno/Localizable.xcstrings` (Italian). Error messages raised in `StenoCore` are looked up in the app's catalog too and must be added to it by hand. To try the Italian interface: `defaults write dev.mameli.steno AppleLanguages -array it`.
- Debug builds accept launch arguments for automated tests (`-smokeTestSeconds`, `-transcribeRecording`, …): see `runSmokeTestIfRequested()` in `Steno/MeetingController.swift`. They refuse to run unless pointed at a test vault, a test data folder and a test Summary server.

## License

MIT, see [LICENSE](LICENSE).
