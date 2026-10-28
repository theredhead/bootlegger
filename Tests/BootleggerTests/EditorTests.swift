import AppKit
import Foundation

@MainActor
enum EditorTests {
    static func run(source: URL) async throws {
        let model = ProjectModel()
        await model.importRecording(from: source)?.value
        defer { model.close() }
        model.playback.seek(1)
        model.setSongStart()
        try SmokeTests.require(
            model.project.songs.count == 1 && model.project.songs[0].start == 1,
            "S creates/selects the first song when needed")
        model.playback.seek(2)
        model.setSongEnd()
        try SmokeTests.require(
            model.project.songs.count == 2 && model.project.songs[0].end == 2, "E finalizes the current song")
        try SmokeTests.require(
            model.selectedSongID == model.project.songs[1].id && model.project.songs[1].start == 2,
            "E selects a new song starting at the same cursor")
        model.playback.seek(3)
        model.setSongEnd()
        try SmokeTests.require(
            model.project.songs.count == 3 && model.project.songs[1].end == 3,
            "successive E marks create successive songs")
        model.selectedSongID = model.project.songs[0].id
        model.playback.seek(1.5)
        model.setSongEnd()
        try SmokeTests.require(
            model.project.songs.count == 3 && model.selectedSongID == model.project.songs[0].id,
            "E does not append when a next song already exists")
        model.selectedSongID = model.project.songs[2].id
        model.playback.seek(model.playback.duration)
        model.setSongEnd()
        try SmokeTests.require(model.project.songs.count == 3, "E at video end does not create an empty song")
        model.playback.seek(0)
        model.setSongEnd()
        try SmokeTests.require(
            model.project.songs[2].end == model.playback.duration && model.status.contains("Range unchanged"),
            "invalid end does not alter the range")

        try transportKeys(model: model)
        let levels = try await AudioLevels.read(url: source, start: 1, end: 3)
        try SmokeTests.require(
            levels.peaks.count == 2000 && levels.interval == 0.001, "bounded audio read has millisecond bins")
        try SmokeTests.require(
            levels.peak(from: 1.1, to: 1.2) > 0.1, "audio display contains measured amplitude")
        try SmokeTests.require(levels.peak(from: 0, to: 0.5) == 0, "outside cached audio is empty")

        let cache = AudioLevels()
        await cache.prescan(url: source, duration: model.playback.duration)?.value
        try SmokeTests.require(
            cache.hasFullCache && !cache.isPrescanning && cache.prescanProgress == 1,
            "one prescan action fills the full concert cache")
        try SmokeTests.require(
            cache.samples?.start == 0 && (cache.samples?.end ?? 0) >= model.playback.duration,
            "prescan covers the entire source")
        let cachedPeaks = cache.samples?.peaks
        cache.request(url: source, position: 4, duration: model.playback.duration)
        try SmokeTests.require(cache.samples?.peaks == cachedPeaks, "seeking reuses the full cache")
        cache.reset()
        try SmokeTests.require(
            !cache.hasFullCache && cache.samples == nil, "changing source clears audio cache")

        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 180, bitsPerSample: 8, samplesPerPixel: 3,
            hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = NSImage(size: NSSize(width: 320, height: 180))
        image.addRepresentation(bitmap)
        let originalArtwork = image.tiffRepresentation!
        let full = try ArtworkProcessor.exportJPEG(originalArtwork, crop: nil)
        let square = try ArtworkProcessor.exportJPEG(originalArtwork, crop: ArtworkCrop())
        let fullBitmap = NSBitmapImageRep(data: full)!
        let squareBitmap = NSBitmapImageRep(data: square)!
        try SmokeTests.require(
            fullBitmap.pixelsWide == 320 && fullBitmap.pixelsHigh == 180,
            "uncropped artwork retains aspect ratio")
        try SmokeTests.require(
            squareBitmap.pixelsWide == 180 && squareBitmap.pixelsHigh == 180,
            "optional artwork crop is square")
        model.setArtwork(image)
        let unchangedArtwork = model.artwork
        model.project.artworkCrop = ArtworkCrop(centerX: 0.4, centerY: 0.6, zoom: 2)
        _ = try ArtworkProcessor.preview(model.artwork!, crop: model.project.artworkCrop)
        try SmokeTests.require(
            model.artwork == unchangedArtwork, "crop/preview preserves original artwork bytes")
        let droppedImage = source.deletingLastPathComponent().appendingPathComponent("Dropped Cover.jpg")
        try full.write(to: droppedImage)
        model.importArtwork(from: droppedImage)
        try SmokeTests.require(
            model.artwork == full && model.project.artworkCrop == nil,
            "new artwork preserves file bytes and resets crop")
        try SmokeTests.require(
            model.project.artworkFilename == "Artwork.jpg", "dropped file keeps its original format")
        let crop = ArtworkCrop(centerX: 0.1, centerY: 0.9, zoom: 2.3)
        let exported = NSBitmapImageRep(data: try ArtworkProcessor.exportJPEG(originalArtwork, crop: crop))!
        try SmokeTests.require(
            exported.pixelsWide == exported.pixelsHigh, "panned fractional crop exports an exact square")
        let croppedDocument = ProjectDocument()
        croppedDocument.model.setArtwork(image)
        croppedDocument.model.project.artworkCrop = crop
        let package = source.deletingLastPathComponent().appendingPathComponent("Artwork Crop.bootlegger")
        try croppedDocument.write(to: package, ofType: "nl.theredhead.bootlegger.project")
        let restored = ProjectDocument()
        try restored.read(from: package, ofType: "nl.theredhead.bootlegger.project")
        try SmokeTests.require(
            restored.model.project.artworkCrop == crop
                && restored.model.artwork == croppedDocument.model.artwork,
            "original artwork and editable crop survive save/reopen")
        restored.close()
        croppedDocument.close()
        let searchPreview = SearchArtworkCropView(frame: NSRect(x: 0, y: 0, width: 310, height: 310))
        searchPreview.image = image
        searchPreview.setZoom(3)
        searchPreview.setCrop(ArtworkCrop(centerX: 0.7, centerY: 0.3, zoom: 3))
        let searchCrop = searchPreview.crop
        try SmokeTests.require(
            searchCrop.zoom == 3 && searchCrop.centerX == 0.7,
            "search preview supports independent pan and zoom")
        model.setArtworkData(full, crop: searchCrop)
        try SmokeTests.require(
            model.artwork == full && model.project.artworkCrop == searchCrop,
            "search crop is applied as editable metadata with original image data")
        searchPreview.image = image
        try SmokeTests.require(searchPreview.crop == ArtworkCrop(), "new search image resets pan/zoom")
        try ArtworkSearchController.validateImage(full)
        model.project.artworkCrop = crop
        model.setArtworkData(full)
        try SmokeTests.require(
            model.artwork == full && model.project.artworkCrop == nil,
            "search selection preserves original image data and resets the crop")
        try SmokeTests.require(
            ["Artwork.jpg", "Artwork.jpeg"].contains(model.project.artworkFilename ?? ""),
            "search selection stores the detected image format")
        let previousArtwork = model.artwork
        model.setArtworkData(Data("<html>not an image</html>".utf8))
        try SmokeTests.require(
            model.artwork == previousArtwork && model.errorMessage != nil,
            "invalid search data does not replace the cover")
        do {
            try ArtworkSearchController.validateImage(Data(count: ArtworkDownload.byteLimit + 1))
            throw BootleggerError.message("Test failed: oversized artwork accepted")
        } catch {
            try SmokeTests.require(error.localizedDescription.contains("30 MB"), "search image byte limit")
        }
        print(
            "PASS: S/E marking, automatic next-song selection, end-of-video behavior, measured audio levels, artwork crop/import, full prescan/reuse/cancellation, transport keys and text focus."
        )
    }
    private static func transportKeys(model: ProjectModel) throws {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = ProjectWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.model = model
        defer { window.close() }
        func key(_ code: UInt16, _ text: String = "", _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            return NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
        }
        model.playback.seek(0)
        try SmokeTests.require(window.handleTransportKey(key(124)), "right arrow is handled")
        try SmokeTests.require(
            model.playback.position == model.playback.duration, "ten-second seek clamps at video end")
        window.handleTransportKey(key(123, "", .shift))
        try SmokeTests.require(
            model.playback.position == model.playback.duration - 1, "shift-left seeks one second")
        window.handleTransportKey(key(123))
        try SmokeTests.require(model.playback.position == 0, "left arrow seeks ten seconds")
        window.handleTransportKey(key(124, "", .shift))
        try SmokeTests.require(model.playback.position == 1, "shift-right seeks one second")
        try SmokeTests.require(
            !window.handleTransportKey(key(1, "s", .command)), "command shortcuts stay available to menus")
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
        window.contentView = editor
        window.makeFirstResponder(editor)
        let songCount = model.project.songs.count
        try SmokeTests.require(
            !window.handleTransportKey(key(1, "s")) && !window.handleTransportKey(key(14, "e"))
                && !window.handleTransportKey(key(49, " ")) && !window.handleTransportKey(key(124)),
            "transport and marking keys leave text editors alone")
        try SmokeTests.require(
            model.project.songs.count == songCount && model.playback.position == 1,
            "typing does not change project ranges or playback")
        try SmokeTests.require(
            window.handleTransportKey(key(36, "\r")) && !window.isEditingText,
            "Return explicitly exits text editing")
        window.makeFirstResponder(editor)
        try SmokeTests.require(
            window.handleTransportKey(key(53)) && !window.isEditingText,
            "Escape explicitly exits text editing")
        try SmokeTests.require(
            window.handleTransportKey(key(124, "", .shift)) && model.playback.position == 2,
            "transport works again after releasing field focus")
    }
}
