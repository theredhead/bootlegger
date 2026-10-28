import AVFoundation
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class ProjectModel: ObservableObject {
    @Published var project = Project() {
        didSet {
            // Repair selection after storage changes, never inside @Published's willSet notification.
            if selectedSong == nil {
                let fallback = project.songs.first?.id
                if selectedSongID != fallback { selectedSongID = fallback }
            }
        }
    }
    @Published private(set) var mediaRevision = 0
    @Published var artwork: Data?
    @Published var selectedSongID: UUID?
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var status = "Open an audio or video recording to begin."
    @Published var exportProgress = 0.0
    @Published var isPreparingExport = false
    @Published private(set) var isExporting = false
    let playback = Playback()
    let audioLevels = AudioLevels()
    @Published var isEditingArtwork = false
    @Published var cropEditorOriginal: NSImage?
    var sourceURL: URL?
    private var stagingDirectory: URL?
    private var mediaTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var artworkSearch: ArtworkSearchController?

    var selectedSong: Song? { return project.songs.first { $0.id == selectedSongID } }

    func song(id: UUID) -> Song? { return project.songs.first { $0.id == id } }

    /// All UI boundary mutations pass through this check; metadata-only edits remain possible for legacy bad ranges.
    @discardableResult
    func updateSong(_ candidate: Song) -> Bool {
        guard let index = project.songs.firstIndex(where: { $0.id == candidate.id }) else { return false }
        let previous = project.songs[index]
        var updated = candidate
        if candidate.start != previous.start || candidate.end != previous.end {
            if playback.duration > 0, candidate.end > playback.duration,
                candidate.end <= playback.duration + 0.001
            {
                updated.end = playback.duration
            }
            guard updated.start.isFinite, updated.end.isFinite, updated.start >= 0,
                updated.end > updated.start
            else {
                status = "Range unchanged: the end must be after the start, and times cannot be negative."
                return false
            }
            guard playback.duration <= 0 || updated.end <= playback.duration else {
                status = "Range unchanged: both boundaries must be within the recording."
                return false
            }
        }
        project.songs[index] = updated
        if updated.start != previous.start || updated.end != previous.end { status = "Song range updated." }
        return true
    }

    func removeSong(id: UUID) {
        guard !isBusy, let index = project.songs.firstIndex(where: { $0.id == id }) else { return }
        var remaining = project.songs
        remaining.remove(at: index)
        if selectedSongID == id {
            selectedSongID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
        project.songs = remaining
    }

    var selectedSongIndex: Int? {
        return project.songs.firstIndex { $0.id == selectedSongID }
    }

    func importRecording() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .audio]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importRecording(from: url)
    }

    static func isRecording(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let type =
            (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        return type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true
            || type?.conforms(to: .audio) == true
    }

    @discardableResult
    func importRecording(from url: URL, confirmReplacement: (() -> Bool)? = nil) -> Task<Void, Never>? {
        guard !isBusy else {
            errorMessage = "Wait for the current operation to finish before importing a recording."
            return nil
        }
        guard Self.isRecording(url) else {
            errorMessage =
                "Choose a local audio or video recording, such as MP4, MOV, M4A, MP3, WAV, AIFF or FLAC. Playback support depends on macOS and the recording's codecs."
            return nil
        }
        if sourceURL != nil {
            let confirmed: Bool
            if let confirmReplacement {
                confirmed = confirmReplacement()
            } else {
                let alert = NSAlert()
                alert.messageText = "Replace the project recording?"
                alert.informativeText =
                    "The existing recording will be replaced with \(url.lastPathComponent). Song ranges, album metadata and artwork will be kept. Check the song ranges against the new recording."
                alert.addButton(withTitle: "Replace Recording")
                alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
                confirmed = alert.runModal() == .alertFirstButtonReturn
            }
            guard confirmed else { return nil }
        }
        isBusy = true
        status = "Importing recording…"
        mediaTask = Task {
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "Bootlegger-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var imported = false
                defer { if !imported { FileCleanup.remove(directory) } }
                let destination = directory.appendingPathComponent(
                    "Recording.\(url.pathExtension.isEmpty ? "media" : url.pathExtension)")
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                try await Task.detached {
                    try FileManager.default.copyItem(at: url, to: destination)
                }.value
                try Task.checkCancellation()
                try await playback.load(destination)
                if let stagingDirectory { FileCleanup.remove(stagingDirectory) }
                imported = true
                stagingDirectory = directory
                sourceURL = destination
                project.videoFilename = destination.lastPathComponent
                if project.album.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    project.album.title = FilenameMetadata.albumTitle(from: url)
                }
                if project.album.year.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    let year = FilenameMetadata.year(from: url)
                {
                    project.album.year = year
                }
                audioLevels.reset()
                mediaRevision += 1
                status =
                    project.songs.contains(where: { !$0.hasValidRange(within: playback.duration) })
                    ? "Recording ready. Some ranges need correction: start must precede end, within the recording."
                    : "Recording ready. Add a song at the playhead."
            } catch {
                errorMessage = error.localizedDescription
                status = "Recording import failed."
            }
            isBusy = false
        }
        return mediaTask
    }

    func openRecording(_ url: URL) {
        isBusy = true
        status = "Opening project recording…"
        mediaTask = Task {
            do {
                try await playback.load(url)
                status =
                    project.songs.contains(where: { !$0.hasValidRange(within: playback.duration) })
                    ? "Project loaded. Some ranges need correction: start must precede end, within the recording."
                    : "Project loaded."
            } catch is CancellationError {
                status = "Opening cancelled."
            } catch { errorMessage = error.localizedDescription }
            isBusy = false
        }
    }

    func addSong() {
        let start = playback.position
        guard playback.duration > start else {
            status = "Move the playhead before the recording's end to start a song."
            return
        }
        let song = Song(
            title: "Track \(project.songs.count + 1)", start: start, end: min(start + 180, playback.duration))
        project.songs.append(song)
        selectedSongID = song.id
        status = "Song added."
    }

    func setSongStart() {
        guard !isBusy, sourceURL != nil else { return }
        if selectedSongIndex == nil { addSong() }
        guard let index = selectedSongIndex else { return }
        var song = project.songs[index]
        song.start = playback.position
        updateSong(song)
    }

    func setSongEnd() {
        guard !isBusy, let index = selectedSongIndex else { return }
        markSongEnd(at: playback.position, duration: playback.duration, index: index)
    }

    /// Finalizing the last listed song creates the next range without seeking or interrupting playback.
    func markSongEnd(at position: Double, duration: Double, index: Int) {
        guard project.songs.indices.contains(index), min(position, duration) > project.songs[index].start
        else {
            status = "Range unchanged: the song end must be after its start."
            return
        }
        var song = project.songs[index]
        song.end = min(position, duration)
        guard updateSong(song) else { return }
        playback.clearPreviewEnd()
        if index == project.songs.count - 1 && position < duration - 0.001 {
            let song = Song(
                title: "Track \(project.songs.count + 1)", start: position, end: min(position + 180, duration)
            )
            project.songs.append(song)
            selectedSongID = song.id
        }
    }

    func selectSong(_ id: UUID) {
        guard song(id: id) != nil else { return }
        selectedSongID = id
    }

    func moveSong(_ id: UUID, offset: Int) {
        guard let index = project.songs.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard project.songs.indices.contains(destination) else { return }
        project.songs.swapAt(index, destination)
    }

    func captureArtwork() {
        guard let sourceURL, playback.hasVideo else {
            errorMessage = "This is an audio-only recording. Drop an image onto the artwork area instead."
            return
        }
        isBusy = true
        mediaTask = Task {
            do {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: sourceURL))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = .zero
                let result = try await generator.image(
                    at: CMTime(seconds: playback.position, preferredTimescale: 600))
                guard
                    let data = NSBitmapImageRep(cgImage: result.image).representation(
                        using: .png, properties: [:])
                else {
                    throw BootleggerError.message("The captured frame could not be stored losslessly.")
                }
                try Task.checkCancellation()
                artwork = data
                project.artworkFilename = "Artwork.png"
                project.artworkCrop = nil
                isEditingArtwork = false
                status = "Album artwork captured."
            } catch { errorMessage = error.localizedDescription }
            isBusy = false
        }
    }

    func importArtwork(from url: URL) {
        guard !isBusy else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            _ = try ArtworkProcessor.originalImage(data)
            artwork = data
            project.artworkFilename =
                "Artwork.\(url.pathExtension.isEmpty ? "image" : url.pathExtension.lowercased())"
            project.artworkCrop = nil
            isEditingArtwork = false
            status = "Album artwork imported."
        } catch { errorMessage = error.localizedDescription }
    }

    func setArtwork(_ image: NSImage) {
        guard !isBusy else { return }
        guard let data = image.tiffRepresentation else {
            errorMessage = "The dropped image could not be stored losslessly."
            return
        }
        artwork = data
        project.artworkFilename = "Artwork.tiff"
        project.artworkCrop = nil
        isEditingArtwork = false
        status = "Album artwork imported."
    }

    func searchArtwork() {
        guard !isBusy else { return }
        if let artworkSearch {
            artworkSearch.show(initialQuery: "") { [weak self] data, crop in
                self?.setArtworkData(data, crop: crop)
            }
            return
        }
        let controller = ArtworkSearchController()
        artworkSearch = controller
        controller.onClose = { [weak self] in self?.artworkSearch = nil }
        controller.canUseSelection = { [weak self] in self?.isBusy == false }
        let terms = [project.album.artist, project.album.title]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let query = terms.isEmpty ? "" : terms.joined(separator: " ") + " album cover"
        controller.show(initialQuery: query) { [weak self] data, crop in
            self?.setArtworkData(data, crop: crop)
        }
    }

    func setArtworkData(_ data: Data, crop: ArtworkCrop? = nil) {
        guard !isBusy else { return }
        do {
            let original = try ArtworkProcessor.originalImage(data)
            artwork = data
            project.artworkFilename = "Artwork.\(ArtworkProcessor.filenameExtension(data))"
            project.artworkCrop = crop?.clamped(
                width: Double(original.width), height: Double(original.height))
            isEditingArtwork = false
            status = "Album artwork selected."
        } catch { errorMessage = error.localizedDescription }
    }

    func beginArtworkCrop() {
        guard !isBusy, let artwork else { return }
        do {
            cropEditorOriginal = try ArtworkProcessor.preview(artwork, crop: nil)
            isEditingArtwork = true
        } catch { errorMessage = error.localizedDescription }
    }

    func exportAudio() {
        guard !isBusy, sourceURL != nil, !project.songs.isEmpty else { return }
        isPreparingExport = true
    }

    func validateExport(_ snapshot: Project) -> Bool {
        do {
            try AudioExporter.validate(project: snapshot, duration: playback.duration)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func exportFiles(_ snapshot: Project, settings: FileExportSettings = FileExportSettings()) {
        guard !isBusy, let sourceURL, validateExport(snapshot) else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a folder for exported audio"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        let cover = artwork
        isBusy = true
        exportProgress = 0
        isExporting = true
        exportTask = Task {
            do {
                let result = try await AudioExporter.export(
                    project: snapshot, artwork: cover, sourceURL: sourceURL, destination: directory,
                    settings: settings
                ) { [weak self] progress, text in
                    self?.exportProgress = progress
                    self?.status = text
                }
                status = "Exported \(snapshot.songs.count) tracks to \(result.lastPathComponent)."
                NSWorkspace.shared.activateFileViewerSelecting([result])
            } catch is CancellationError {
                status = "Export cancelled."
            } catch {
                errorMessage = error.localizedDescription
                status = "Export failed."
            }
            isBusy = false
            isExporting = false
            exportTask = nil
        }
    }

    func cancelExport() { exportTask?.cancel() }

    func close() {
        artworkSearch?.close()
        artworkSearch = nil
        mediaTask?.cancel()
        exportTask?.cancel()
        playback.stop()
        audioLevels.reset()
        if let stagingDirectory { FileCleanup.remove(stagingDirectory) }
    }
}
