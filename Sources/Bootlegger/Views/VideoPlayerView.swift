import AVKit
import SwiftUI

/// Uses AVKit's native macOS player and transport controls.
struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let importRecording: (URL) -> Void

    func makeNSView(context: Context) -> AVPlayerView {
        let view = DroppablePlayerView()
        view.importRecording = importRecording
        view.registerForDraggedTypes([.fileURL])
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
        (view as? DroppablePlayerView)?.importRecording = importRecording
    }
}

/// AVPlayerView otherwise consumes file drops without updating the project document.
@MainActor
private final class DroppablePlayerView: AVPlayerView {
    var importRecording: ((URL) -> Void)?

    private func sourceURL(_ sender: any NSDraggingInfo) -> URL? {
        let urls =
            sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        guard let urls, urls.count == 1, let url = urls.first, ProjectModel.isRecording(url) else {
            return nil
        }
        return url
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return sourceURL(sender) == nil ? [] : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return draggingEntered(sender)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        return sourceURL(sender) != nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let url = sourceURL(sender) else { return false }
        importRecording?(url)
        return true
    }
}
