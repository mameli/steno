# Native Swift app, not Tauri

Although familiar with Tauri/Rust (a fork of Handy), Steno is a SwiftUI menu bar app. The hard parts are all native macOS APIs: Core Audio process taps for system audio, microphone, EventKit, Keychain, notifications and TCC permissions bound to the identity of the signed app. From Rust they would need hand-written Objective-C bindings, i.e. the riskiest part of the project done the most awkward way. Python (rumps/pyobjc) was also ruled out because packaging and permissions are fragile.
