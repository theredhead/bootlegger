import AppKit
import SwiftUI

/// Supplies row geometry to the window's mouse-down handler without intercepting controls.
struct SongRowSelectionRegion: NSViewRepresentable {
    let songID: UUID

    func makeNSView(context: Context) -> SongRowRegionView {
        let view = SongRowRegionView()
        view.songID = songID
        return view
    }

    func updateNSView(_ view: SongRowRegionView, context: Context) { view.songID = songID }
}

@MainActor
final class SongRowRegionView: NSView {
    var songID: UUID?
    private weak var registeredWindow: ProjectWindow?

    override func hitTest(_ point: NSPoint) -> NSView? { return nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registeredWindow?.unregisterSongRow(self)
        registeredWindow = window as? ProjectWindow
        registeredWindow?.registerSongRow(self)
    }

    func containsWindowPoint(_ point: NSPoint) -> Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return false }
        let local = convert(point, from: nil)
        return bounds.contains(local) && visibleRect.contains(local)
    }
}
