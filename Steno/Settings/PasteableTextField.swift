import AppKit
import SwiftUI

/// Campo di testo in cui ⌘V, ⌘C, ⌘X, ⌘A e ⌘Z funzionano sempre. Le app che vivono solo nella
/// barra dei menu non hanno il menu Composizione, e senza quello i campi SwiftUI ignorano le scorciatoie.
struct PasteableTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isSecure = false

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = isSecure ? ShortcutSecureTextField() : ShortcutTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.lineBreakMode = .byTruncatingTail
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

/// Inoltra le scorciatoie di modifica all'editor del campo, al posto del menu Composizione che manca.
private func handleEditingShortcut(_ event: NSEvent, in field: NSTextField) -> Bool {
    guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
          let key = event.charactersIgnoringModifiers?.lowercased(),
          let editor = field.currentEditor()
    else { return false }
    switch key {
    case "v": editor.paste(nil)
    case "c": editor.copy(nil)
    case "x": editor.cut(nil)
    case "a": editor.selectAll(nil)
    case "z": editor.undoManager?.undo()
    default: return false
    }
    return true
}

private final class ShortcutTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditingShortcut(event, in: self) || super.performKeyEquivalent(with: event)
    }
}

private final class ShortcutSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditingShortcut(event, in: self) || super.performKeyEquivalent(with: event)
    }
}
