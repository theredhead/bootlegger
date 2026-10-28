import AppKit

@MainActor
enum RowSelectionTests {
    static func run() throws {
        let model = ProjectModel()
        let first = Song(title: "First", start: 0, end: 1)
        let second = Song(title: "Second", start: 1, end: 2)
        model.project.songs = [first, second]
        let window = ProjectWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.model = model
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let firstRegion = SongRowRegionView(frame: NSRect(x: 0, y: 0, width: 600, height: 60))
        firstRegion.songID = first.id
        let secondRegion = SongRowRegionView(frame: NSRect(x: 0, y: 70, width: 600, height: 60))
        secondRegion.songID = second.id
        let field = NSTextField(string: "Second")
        field.frame = NSRect(x: 80, y: 85, width: 140, height: 24)
        let editor = NSTextView(frame: NSRect(x: 80, y: 10, width: 140, height: 24))
        let label = NSTextField(labelWithString: "Timestamp")
        label.frame = NSRect(x: 250, y: 85, width: 100, height: 24)
        let action = SelectionAction(model: model)
        let button = NSButton(title: "Play", target: action, action: #selector(SelectionAction.clicked(_:)))
        button.frame = NSRect(x: 15, y: 85, width: 60, height: 24)
        for view in [firstRegion, secondRegion, field, editor, label, button] as [NSView] {
            root.addSubview(view)
        }
        window.contentView = root
        defer {
            window.close()
            model.close()
        }
        for point in [
            NSPoint(x: 4, y: 74), NSPoint(x: 595, y: 125), NSPoint(x: 100, y: 95), NSPoint(x: 280, y: 95),
            NSPoint(x: 40, y: 95),
        ] {
            model.selectSong(first.id)
            window.handlePointerClick(at: root.convert(point, to: nil))
            try SmokeTests.require(
                model.selectedSongID == second.id, "padding, fields, labels and controls all select their row"
            )
        }
        model.selectSong(first.id)
        window.makeFirstResponder(editor)
        window.handlePointerClick(at: field.convert(NSPoint(x: 10, y: 10), to: nil))
        try SmokeTests.require(
            model.selectedSongID == second.id && !window.isEditingText,
            "changing rows commits the old editor before selecting")
        model.selectSong(first.id)
        window.handlePointerClick(at: button.convert(NSPoint(x: 10, y: 10), to: nil))
        button.performClick(nil)
        try SmokeTests.require(action.selectedAtAction == second.id, "button action runs after row selection")
        // Actions that deliberately select a successor must not be undone by a later row tap.
        model.selectSong(first.id)
        try SmokeTests.require(
            model.selectedSongID == first.id, "no deferred mouse-up selection overrides a control action")
        secondRegion.isHidden = true
        window.handlePointerClick(at: root.convert(NSPoint(x: 400, y: 100), to: nil))
        try SmokeTests.require(model.selectedSongID == first.id, "hidden row geometry cannot select a track")
        secondRegion.isHidden = false
        model.removeSong(id: second.id)
        window.handlePointerClick(at: root.convert(NSPoint(x: 400, y: 100), to: nil))
        try SmokeTests.require(
            model.selectedSongID == first.id, "stale deleted row geometry cannot select a missing track")
        print(
            "PASS: entire-row mouse-down selection, focus handoff, control actions, hidden/deleted row guards."
        )
    }
}

@MainActor
private final class SelectionAction: NSObject {
    let model: ProjectModel
    var selectedAtAction: UUID?
    init(model: ProjectModel) { self.model = model }
    @objc func clicked(_ sender: Any?) { selectedAtAction = model.selectedSongID }
}
