import AppKit
import Combine
import SwiftUI

/// A package document owns its media copy and keeps every window's state independent.
@MainActor
@objc(ProjectDocument)
final class ProjectDocument: NSDocument {
    let model = ProjectModel()
    private var subscriptions = Set<AnyCancellable>()
    private var restoring = false

    override init() {
        super.init()
        hasUndoManager = true
        model.$mediaRevision.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            // Prior undo entries may refer to media that has just been replaced.
            self.undoManager?.removeAllActions()
            self.updateChangeCount(.changeDone)
        }.store(in: &subscriptions)
        model.$project.dropFirst().sink { [weak self] project in
            guard let self, !self.restoring, project != self.model.project else { return }
            let previous = self.model.project
            // Importing establishes the document's media; ordinary edits are undoable.
            guard previous.videoFilename == project.videoFilename else {
                self.updateChangeCount(.changeDone)
                return
            }
            self.undoManager?.registerUndo(withTarget: self) { document in
                document.model.project = previous
            }
            self.undoManager?.setActionName("Edit Project")
        }.store(in: &subscriptions)
        model.$artwork.dropFirst().sink { [weak self] artwork in
            guard let self, !self.restoring, artwork != self.model.artwork else { return }
            let previous = self.model.artwork
            self.undoManager?.registerUndo(withTarget: self) { document in
                document.model.artwork = previous
            }
            self.undoManager?.setActionName("Capture Cover")
        }.store(in: &subscriptions)
    }

    override class var autosavesInPlace: Bool { return false }

    override func makeWindowControllers() {
        let window = ProjectWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.model = model
        window.installTransportKeys()
        window.minSize = NSSize(width: 1100, height: 680)
        window.center()
        window.contentView = NSHostingView(rootView: ProjectView(model: model))
        addWindowController(NSWindowController(window: window))
        window.title = displayName
    }

    override func read(from url: URL, ofType typeName: String) throws {
        // NSDocument performs synchronous document I/O on the main thread by default.
        try MainActor.assumeIsolated { try readProject(from: url) }
    }

    private func readProject(from url: URL) throws {
        let data = try Data(contentsOf: url.appendingPathComponent("Project.json"))
        let project = try JSONDecoder().decode(Project.self, from: data)
        guard project.version == 1 else {
            throw BootleggerError.message(
                "This project uses an unsupported format version (\(project.version)).")
        }
        func containedURL(_ filename: String) throws -> URL {
            guard !filename.isEmpty, filename == (filename as NSString).lastPathComponent, filename != ".",
                filename != ".."
            else {
                throw BootleggerError.message("The project contains an invalid media filename.")
            }
            let candidate = url.appendingPathComponent(filename)
            guard
                candidate.resolvingSymlinksInPath().deletingLastPathComponent()
                    == url.resolvingSymlinksInPath()
            else {
                throw BootleggerError.message("Project media must be stored inside the project bundle.")
            }
            return candidate
        }
        let video = try project.videoFilename.map { try containedURL($0) }
        if let video, !FileManager.default.fileExists(atPath: video.path) {
            throw BootleggerError.message(
                "The project recording is missing. Restore \(video.lastPathComponent) inside the project bundle."
            )
        }
        let cover = try project.artworkFilename.map { try Data(contentsOf: containedURL($0)) }
        restoring = true
        model.project = project
        model.artwork = cover
        model.sourceURL = video
        model.selectedSongID = project.songs.first?.id
        restoring = false
        if let video { model.openRecording(video) }
    }

    override func write(to url: URL, ofType typeName: String) throws {
        try MainActor.assumeIsolated { try writeProject(to: url) }
    }

    override func write(
        to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
        originalContentsURL: URL?
    ) throws {
        try MainActor.assumeIsolated { try writeProject(to: url, originalContentsURL: originalContentsURL) }
    }

    private func writeProject(to url: URL, originalContentsURL: URL? = nil) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let filename = model.project.videoFilename {
            var source = model.sourceURL
            if source.map({ FileManager.default.fileExists(atPath: $0.path) }) != true,
                let original = originalContentsURL?.appendingPathComponent(filename),
                FileManager.default.fileExists(atPath: original.path)
            {
                source = original
            }
            guard let video = source else {
                throw BootleggerError.message(
                    "The project recording is unavailable and the project cannot be saved.")
            }
            let target = url.appendingPathComponent(filename)
            if video.standardizedFileURL != target.standardizedFileURL {
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: video, to: target)
            }
        }
        if let artwork = model.artwork, let filename = model.project.artworkFilename {
            try artwork.write(to: url.appendingPathComponent(filename), options: .atomic)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(model.project).write(
            to: url.appendingPathComponent("Project.json"), options: .atomic)
    }

    override func save(
        to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if error == nil, let self, let filename = self.model.project.videoFilename,
                let currentURL = self.fileURL
            {
                let video = currentURL.appendingPathComponent(filename)
                self.model.audioLevels.relocateSource(to: video)
                self.model.sourceURL = video
            }
            completionHandler(error)
        }
    }

    @objc func importRecordingFromMenu(_ sender: Any?) { model.importRecording() }

    @objc func exportAlbumFromMenu(_ sender: Any?) { model.exportAudio() }

    @objc func searchArtworkFromMenu(_ sender: Any?) { model.searchArtwork() }

    @objc func captureArtworkFromMenu(_ sender: Any?) { model.captureArtwork() }

    @objc func editArtworkCropFromMenu(_ sender: Any?) { model.beginArtworkCrop() }

    @objc func removeArtworkCropFromMenu(_ sender: Any?) { model.project.artworkCrop = nil }

    @objc func prescanAudioLevelsFromMenu(_ sender: Any?) {
        guard let url = model.sourceURL else { return }
        model.audioLevels.prescan(url: url, duration: model.playback.duration)
    }

    @objc func cancelAudioPrescanFromMenu(_ sender: Any?) { model.audioLevels.cancelPrescan() }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(importRecordingFromMenu(_:)) { return !model.isBusy }
        if menuItem.action == #selector(exportAlbumFromMenu(_:)) {
            return !model.isBusy && model.sourceURL != nil && !model.project.songs.isEmpty
        }
        if menuItem.action == #selector(prescanAudioLevelsFromMenu(_:)) {
            return !model.isBusy && model.sourceURL != nil && !model.audioLevels.isPrescanning
                && !model.audioLevels.hasFullCache
        }
        if menuItem.action == #selector(cancelAudioPrescanFromMenu(_:)) {
            return model.audioLevels.isPrescanning
        }
        if menuItem.action == #selector(searchArtworkFromMenu(_:)) { return !model.isBusy }
        if menuItem.action == #selector(captureArtworkFromMenu(_:)) {
            return !model.isBusy && model.sourceURL != nil && model.playback.hasVideo
        }
        if menuItem.action == #selector(editArtworkCropFromMenu(_:)) {
            return !model.isBusy && model.artwork != nil
        }
        if menuItem.action == #selector(removeArtworkCropFromMenu(_:)) {
            return !model.isBusy && model.project.artworkCrop != nil
        }
        return super.validateMenuItem(menuItem)
    }

    override func close() {
        model.close()
        super.close()
    }
}
