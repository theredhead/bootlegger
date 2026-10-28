import AppKit
import SwiftUI

struct TimeField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        TimestampInput(title: title, value: $value).frame(width: 105)
    }
}

/// The field editor delegates arrow commands so nudging works while text is being edited.
private struct TimestampInput: NSViewRepresentable {
    let title: String
    @Binding var value: Double

    func makeCoordinator() -> Coordinator { return Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: Timestamp.string(value))
        field.isEditable = true
        field.isSelectable = true
        field.bezelStyle = .roundedBezel
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.setAccessibilityLabel(title)
        field.toolTip = "\(title): seconds, mm:ss.mmm, or hh:mm:ss.mmm. Up/down nudges by 0.1 second."
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.currentEditor() == nil { field.stringValue = Timestamp.string(value) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TimestampInput

        init(parent: TimestampInput) { self.parent = parent }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            commit(field)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
            -> Bool
        {
            guard let field = control as? NSTextField else { return false }
            if commandSelector == #selector(NSResponder.moveUp(_:))
                || commandSelector == #selector(NSResponder.moveDown(_:))
            {
                let delta = commandSelector == #selector(NSResponder.moveUp(_:)) ? 0.1 : -0.1
                store(max(0, (Timestamp.seconds(field.stringValue) ?? parent.value) + delta), in: field)
                textView.selectAll(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.cancelOperation(_:))
            {
                commit(field)
                if let window = field.window as? ProjectWindow {
                    window.focusPlayback()
                } else {
                    field.window?.makeFirstResponder(nil)
                }
                return true
            }
            return false
        }

        @discardableResult
        private func commit(_ field: NSTextField) -> Bool {
            guard let seconds = Timestamp.seconds(field.stringValue) else {
                field.stringValue = Timestamp.string(parent.value)
                field.textColor = .systemRed
                field.toolTip =
                    "Invalid timestamp. Enter seconds, mm:ss.mmm, or hh:mm:ss.mmm. The previous value is retained until corrected."
                NSSound.beep()
                return false
            }
            return store(seconds, in: field)
        }

        @discardableResult
        private func store(_ seconds: Double, in field: NSTextField) -> Bool {
            parent.value = seconds
            let accepted = abs(parent.value - seconds) <= 0.001
            field.stringValue = Timestamp.string(parent.value)
            field.textColor = accepted ? .labelColor : .systemRed
            field.toolTip =
                accepted
                ? "Return or Escape returns to playback. Up/down nudges by 0.1 second."
                : "Range unchanged. Start must be before end, and both times must be within the recording."
            return accepted
        }
    }
}
