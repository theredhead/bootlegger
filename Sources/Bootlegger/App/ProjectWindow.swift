import AppKit

/// Document-local transport keys leave text editing and modified menu shortcuts alone.
@MainActor
final class ProjectWindow: NSWindow {
    weak var model: ProjectModel?
    private var keyMonitor: Any?
    private let songRows = NSHashTable<SongRowRegionView>.weakObjects()

    func installTransportKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) {
            [weak self] event in
            guard let self, event.window === self else { return event }
            if event.type == .leftMouseDown {
                self.handlePointerClick(at: event.locationInWindow)
                return event
            }
            return self.handleTransportKey(event) ? nil : event
        }
    }

    @discardableResult
    func handleTransportKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if isEditingText {
            if [36, 76, 53].contains(event.keyCode) {
                focusPlayback()
                return true
            }
            return false
        }
        guard let model, !model.isBusy, model.sourceURL != nil else { return false }
        if event.isARepeat
            && (event.keyCode == 49
                || ["s", "e"].contains(event.charactersIgnoringModifiers?.lowercased() ?? ""))
        {
            return true
        }
        switch event.keyCode {
        case 49: model.playback.toggle()
        case 123:
            model.playback.seek(model.playback.position - (event.modifierFlags.contains(.shift) ? 1 : 10))
        case 124:
            model.playback.seek(model.playback.position + (event.modifierFlags.contains(.shift) ? 1 : 10))
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "s": model.setSongStart()
            case "e": model.setSongEnd()
            default: return false
            }
        }
        return true
    }

    var isEditingText: Bool {
        if let field = firstResponder as? NSTextField { return field.isEditable }
        if let text = firstResponder as? NSText { return text.isEditable }
        return false
    }

    func focusPlayback() {
        endEditing(for: nil)
        makeFirstResponder(self)
    }

    func registerSongRow(_ view: SongRowRegionView) { songRows.add(view) }

    func unregisterSongRow(_ view: SongRowRegionView) { songRows.remove(view) }

    func handlePointerClick(at point: NSPoint) {
        let clickedSong = songRows.allObjects.first { view in
            guard let id = view.songID, model?.song(id: id) != nil else { return false }
            return view.containsWindowPoint(point)
        }?.songID
        let changesRow = clickedSong != nil && clickedSong != model?.selectedSongID
        if isEditingText && (changesRow || !hitsTextEditor(at: point)) {
            focusPlayback()
        }
        if let clickedSong, model?.isBusy == false { model?.selectSong(clickedSong) }
    }

    private func hitsTextEditor(at locationInWindow: NSPoint) -> Bool {
        guard let root = contentView else { return false }
        // NSView.hitTest expects a point in the receiver's superview coordinates.
        let point = root.superview?.convert(locationInWindow, from: nil) ?? locationInWindow
        var view = root.hitTest(point)
        while let current = view {
            if let field = current as? NSTextField, field.isEditable { return true }
            if let text = current as? NSText, text.isEditable { return true }
            view = current.superview
        }
        return false
    }

    override func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        super.close()
    }
}
