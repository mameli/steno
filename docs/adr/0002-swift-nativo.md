# App nativa in Swift, non Tauri

Pur avendo familiarità con Tauri/Rust (fork di Handy), Steno è un'app SwiftUI nella barra dei menu. Le parti difficili sono tutte API native macOS: Core Audio process tap per l'audio di sistema, microfono, EventKit, Keychain, notifiche e permessi TCC legati all'identità dell'app firmata. Da Rust richiederebbero binding Objective-C scritti a mano, cioè la parte più rischiosa del progetto fatta nel modo più scomodo. Scartato anche Python (rumps/pyobjc) per la fragilità di packaging e permessi.
