# Steno

macOS menu bar app that records meetings and writes their Transcript and Summary into an Obsidian Vault, using local providers or providers hosted in the EU. See [docs/SPEC.md](docs/SPEC.md), the glossary in [CONTEXT.md](CONTEXT.md) and the decisions in [docs/adr](docs/adr/).

## Build

Requires Xcode 16+ (the project uses synchronized folders) and macOS 15+.

```sh
xcodebuild -project Steno.xcodeproj -scheme Steno -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Steno.app
```

Domain logic tests:

```sh
cd StenoCore && swift test
```

## Signing

Without configuration the app is signed ad hoc and macOS may ask for the permissions again after every build. For a stable signature copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (ignored by git) and fill in the Team ID of your Personal Team.

## Localization

User-facing strings are written in English in the code and translated in `Steno/Localizable.xcstrings` (Italian). New strings are picked up by Xcode at build time; `xcodebuild -exportLocalizations -project Steno.xcodeproj -localizationPath <folder> -exportLanguage it` lists them. Error messages raised in `StenoCore` are looked up in the app's catalog as well and must be added to it by hand.

## Manual tests

[docs/TESTING.md](docs/TESTING.md) lists the checks to run by hand.
