# Steno

App macOS nella barra dei menu che registra le riunioni e ne scrive Trascrizione e Riepilogo in un vault Obsidian, con provider locali o ospitati in UE. Vedi [docs/SPEC.md](docs/SPEC.md) e il glossario in [CONTEXT.md](CONTEXT.md).

## Build

Richiede Xcode 16+ (il progetto usa cartelle sincronizzate) e macOS 15+.

```sh
xcodebuild -project Steno.xcodeproj -scheme Steno -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Steno.app
```

Test della logica di dominio:

```sh
cd StenoCore && swift test
```

## Firma

Senza configurazione l'app è firmata ad-hoc e macOS può chiedere di nuovo i permessi a ogni build. Per una firma stabile copia `Config/Local.xcconfig.example` in `Config/Local.xcconfig` (ignorato da git) e inserisci il Team ID del tuo Personal Team.
