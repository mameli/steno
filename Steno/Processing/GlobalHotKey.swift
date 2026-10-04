import Carbon.HIToolbox

/// Scorciatoia da tastiera valida in qualsiasi app (⌃⌥⌘R per avviare e fermare la Riunione).
///
/// Carbon chiama il gestore sul main thread; `action` non cambia dopo l'inizializzazione.
final class GlobalHotKey: @unchecked Sendable {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor @Sendable () -> Void
    /// Falso se un'altra app usa già la stessa combinazione.
    private(set) var isRegistered = false

    init(
        keyCode: Int = kVK_ANSI_R, modifiers: Int = controlKey | optionKey | cmdKey,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { hotKey.action() } }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        let id = EventHotKeyID(signature: OSType(0x5354_4E4F), id: 1) // "STNO"
        isRegistered = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
