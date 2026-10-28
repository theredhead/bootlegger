import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Accepts both Finder image files and image data dragged from another app.
struct ArtworkDropTarget: NSViewRepresentable {
    @ObservedObject var model: ProjectModel

    func makeNSView(context: Context) -> ImageDropView {
        let view = ImageDropView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageFrameStyle = .grayBezel
        view.registerForDraggedTypes([.fileURL, .tiff, .png])
        view.setAccessibilityLabel("Album artwork; drop an image here")
        return view
    }

    func updateNSView(_ view: ImageDropView, context: Context) {
        view.model = model
        view.updateArtwork(model.artwork, crop: model.project.artworkCrop)
    }
}

@MainActor
final class ImageDropView: NSImageView {
    weak var model: ProjectModel?
    private var previewSource: Data?
    private var previewCrop: ArtworkCrop?
    private var hasPreview = false

    func updateArtwork(_ data: Data?, crop: ArtworkCrop?) {
        guard !hasPreview || previewSource != data || previewCrop != crop else { return }
        previewSource = data
        previewCrop = crop
        hasPreview = true
        image =
            data.flatMap { try? ArtworkProcessor.preview($0, crop: crop) }
            ?? NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: "Drop album artwork")
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { model?.beginArtworkCrop() } else { super.mouseDown(with: event) }
    }

    private func fileURL(_ sender: any NSDraggingInfo) -> URL? {
        let urls =
            sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        guard let urls, urls.count == 1 else { return nil }
        return urls.first
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard model?.isBusy == false else { return [] }
        if let url = fileURL(sender) {
            return UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true ? .copy : []
        }
        return NSImage.canInit(with: sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return draggingEntered(sender)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        return draggingEntered(sender) == .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard draggingEntered(sender) == .copy, let model else { return false }
        if let url = fileURL(sender) {
            model.importArtwork(from: url)
        } else if let image = NSImage(pasteboard: sender.draggingPasteboard) {
            model.setArtwork(image)
        } else {
            return false
        }
        return true
    }
}
