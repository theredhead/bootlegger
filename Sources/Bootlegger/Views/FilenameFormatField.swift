import AppKit
import SwiftUI

/// Native token field preserves literal separators and supports token dragging/reordering.
struct FilenameFormatField: NSViewRepresentable {
    @Binding var template: String

    func makeCoordinator() -> Coordinator { return Coordinator(template: $template) }

    func makeNSView(context: Context) -> NSTokenField {
        let field = NSTokenField()
        field.delegate = context.coordinator
        field.tokenizingCharacterSet = CharacterSet(charactersIn: "\n")
        field.tokenStyle = .rounded
        field.placeholderString = "Drag tokens here and type separators"
        field.setAccessibilityLabel("Filename format")
        field.objectValue = FilenameToken.pieces(template)
        return field
    }

    func updateNSView(_ field: NSTokenField, context: Context) {
        context.coordinator.template = $template
        guard field.currentEditor() == nil else { return }
        if (field.objectValue as? [String] ?? []).joined() != template {
            field.objectValue = FilenameToken.pieces(template)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTokenFieldDelegate {
        var template: Binding<String>
        init(template: Binding<String>) { self.template = template }

        func controlTextDidChange(_ notification: Notification) { synchronize(notification) }
        func controlTextDidEndEditing(_ notification: Notification) {
            synchronize(notification)
            if let field = notification.object as? NSTokenField {
                field.objectValue = FilenameToken.pieces(template.wrappedValue)
            }
        }

        private func synchronize(_ notification: Notification) {
            guard let field = notification.object as? NSTokenField else { return }
            template.wrappedValue = (field.objectValue as? [String] ?? []).joined()
        }

        func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject object: Any) -> String?
        {
            guard let value = object as? String else { return nil }
            return FilenameToken(rawValue: value)?.title ?? value
        }

        func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject object: Any) -> String?
        {
            return object as? String
        }

        func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any?
        {
            return editingString
        }

        func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject object: Any)
            -> NSTokenField.TokenStyle
        {
            return (object as? String).flatMap(FilenameToken.init(rawValue:)) == nil ? .none : .rounded
        }

        func tokenField(_ tokenField: NSTokenField, readFrom pasteboard: NSPasteboard) -> [Any]? {
            guard let text = pasteboard.string(forType: .string) else { return nil }
            return FilenameToken.pieces(text)
        }

        func tokenField(
            _ tokenField: NSTokenField, writeRepresentedObjects objects: [Any],
            to pasteboard: NSPasteboard
        ) -> Bool {
            pasteboard.clearContents()
            return pasteboard.setString((objects as? [String] ?? []).joined(), forType: .string)
        }
    }
}
