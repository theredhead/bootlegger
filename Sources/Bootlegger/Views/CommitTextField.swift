import AppKit
import SwiftUI

/// Native text editing commits and explicitly returns focus to the document's transport.
struct CommitTextField: NSViewRepresentable {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    func makeCoordinator() -> Coordinator { return Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = title
        field.bezelStyle = .roundedBezel
        field.isEditable = true
        field.isSelectable = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel(title)
        field.toolTip = "Return or Escape commits the text and returns to playback."
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.currentEditor() == nil { field.stringValue = text }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommitTextField
        init(parent: CommitTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
            -> Bool
        {
            guard
                commandSelector == #selector(NSResponder.insertNewline(_:))
                    || commandSelector == #selector(NSResponder.cancelOperation(_:)),
                let field = control as? NSTextField
            else { return false }
            parent.text = field.stringValue
            if let window = field.window as? ProjectWindow {
                window.focusPlayback()
            } else {
                field.window?.makeFirstResponder(nil)
            }
            return true
        }
    }
}
