import Carbon.HIToolbox

/// Keyboard shortcut that works in any app: ⌃⌥⌘R starts and stops the Meeting, ⌃⌥⌘M marks a moment.
///
/// Carbon calls the handler on the main thread; `action` never changes after init.
final class GlobalHotKey: @unchecked Sendable {
    private static let signature = OSType(0x5354_4E4F) // "STNO"

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32
    private let action: @MainActor @Sendable () -> Void
    /// False if another app already uses the same combination.
    private(set) var isRegistered = false

    /// `id` tells Steno's shortcuts apart: every handler sees every shortcut and acts only on its own.
    init(
        id: UInt32, keyCode: Int, modifiers: Int = controlKey | optionKey | cmdKey,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                // Another of Steno's shortcuts: left to its own handler.
                guard status == noErr, pressed.signature == GlobalHotKey.signature, pressed.id == hotKey.id else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async { MainActor.assumeIsolated { hotKey.action() } }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        isRegistered = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
