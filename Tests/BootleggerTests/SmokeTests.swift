import AVFoundation
import AppKit
import Foundation

/// Runs native export and document checks without importing anything into Apple Music.
@main
@MainActor
struct SmokeTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw BootleggerError.message("Test failed: \(message)") }
    }

    static func main() async throws {
        let undoDocument = ProjectDocument()
        undoDocument.undoManager?.groupsByEvent = false
        undoDocument.undoManager?.beginUndoGrouping()
        undoDocument.model.project.album.title = "Undo Example"
        undoDocument.undoManager?.endUndoGrouping()
        undoDocument.undoManager?.undo()
        try require(undoDocument.model.project.album.title.isEmpty, "undo metadata edit")
        undoDocument.undoManager?.redo()
        try require(undoDocument.model.project.album.title == "Undo Example", "redo metadata edit")
        undoDocument.close()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BootleggerTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try require(Timestamp.seconds("1:02:03.125") == 3723.125, "hour timestamp")
        try require(Timestamp.seconds("1:60") == nil, "invalid seconds")
        try require(Timestamp.seconds("nan") == nil, "nonfinite timestamp")
        try require(Timestamp.seconds("1e300") == nil, "overflow timestamp")
        try require(Timestamp.seconds("1.5:00") == nil, "fractional minutes rejected")
        try require(
            AudioExporter.safeFilename(String(repeating: "🎵", count: 100)).utf8.count <= 180,
            "Unicode filename byte limit")
        try require(Timestamp.string(59.9996) == "01:00.000", "timestamp carry")
        let audio = directory.appendingPathComponent("Source.wav")
        try writeWave(to: audio)
        let source = try await MediaFixture.movie(in: directory, audioURL: audio)
        let original = try Data(contentsOf: source)
        try await EditorTests.run(source: source)
        try await TrackDeletionTests.run()
        try await EditingSafetyTests.run(source: source)
        try ExportPlanTests.run()
        try await FileExportTests.run(source: source, directory: directory)
        try RowSelectionTests.run()
        try ArtworkPaddingTests.run()
        try await AudioRecordingTests.run(audio: audio)
        try require(ProjectModel.isRecording(source), "MOV accepted for import")
        try require(
            ProjectModel.isRecording(directory.appendingPathComponent("Concert.mp4")),
            "MP4 accepted for import")
        try require(ProjectModel.isRecording(audio), "audio-only recording accepted for import")
        let imported = ProjectDocument()
        await imported.model.importRecording(from: source)?.value
        try require(
            imported.model.sourceURL != nil && imported.model.errorMessage == nil, "shared video import")
        imported.model.project.album.title = "Keep This Album"
        imported.model.project.songs = [Song(title: "Keep This Song", start: 1, end: 3)]
        let priorURL = imported.model.sourceURL
        let cancelledReplacement = imported.model.importRecording(from: source, confirmReplacement: { false })
        try require(
            cancelledReplacement == nil && imported.model.sourceURL == priorURL,
            "cancel replacement preserves video")
        imported.updateChangeCount(.changeCleared)
        await imported.model.importRecording(from: source, confirmReplacement: { true })?.value
        try require(imported.model.sourceURL != priorURL, "confirmed replacement installs a new media copy")
        try require(imported.isDocumentEdited, "same-extension replacement marks the project dirty")
        try require(
            imported.model.project.album.title == "Keep This Album"
                && imported.model.project.songs.count == 1, "replacement preserves metadata and ranges")
        let replacementURL = imported.model.sourceURL
        let brokenVideo = directory.appendingPathComponent("Broken.mp4")
        try Data("Not a movie".utf8).write(to: brokenVideo)
        await imported.model.importRecording(from: brokenVideo, confirmReplacement: { true })?.value
        try require(
            imported.model.sourceURL == replacementURL && imported.model.errorMessage != nil,
            "failed replacement keeps the working video")
        imported.close()

        var project = Project()
        project.videoFilename = "Video.mov"
        project.album = Album(
            title: "Test Concert", artist: "Test Artist", year: "2026", venue: "Test Hall", genre: "Live")
        project.songs = [
            Song(title: "Opening", start: 0.5, end: 2.25),
            Song(title: "Overlap", artist: "Guest Artist", start: 1.5, end: 4.75),
        ]
        try AudioExporter.validate(project: project, duration: 6)
        var invalid = project
        invalid.songs[0].end = 99
        do {
            try AudioExporter.validate(project: invalid, duration: 6)
            throw BootleggerError.message("Invalid range was accepted")
        } catch BootleggerError.message(let message) {
            try require(message.contains("invalid range"), "range rejection")
        }
        let forbiddenDestination = directory.appendingPathComponent("Invalid.bootlegger")
        try FileManager.default.createDirectory(at: forbiddenDestination, withIntermediateDirectories: true)
        do {
            _ = try await AudioExporter.export(
                project: project, artwork: nil, sourceURL: source, destination: forbiddenDestination
            ) { _, _ in }
            throw BootleggerError.message("Test failed: export inside project was accepted")
        } catch {
            try require(
                error.localizedDescription.contains("outside the project bundle"),
                "reject exports inside bundles")
        }
        let beforeCancellation = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let cancelledExport = Task {
            try await AudioExporter.export(
                project: project, artwork: nil, sourceURL: source, destination: directory
            ) { _, _ in }
        }
        cancelledExport.cancel()
        do {
            _ = try await cancelledExport.value
            throw BootleggerError.message("Test failed: cancelled export succeeded")
        } catch is CancellationError {
            let afterCancellation = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .sorted()
            try require(beforeCancellation == afterCancellation, "cancelled export leaves no partial output")
        }
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 3,
            hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let cover = bitmap.representation(using: .jpeg, properties: [:])!
        project.artworkFilename = "Artwork.jpg"
        project.artworkCrop = ArtworkCrop(zoom: 2)
        let output = try await AudioExporter.export(
            project: project, artwork: cover, sourceURL: source, destination: directory
        ) { _, _ in }
        let files = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try require(files.count == 2, "two exported songs")
        for (index, file) in files.enumerated() {
            let asset = AVURLAsset(url: file)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            try require(audioTracks.count == 1 && videoTracks.isEmpty, "export contains audio only")
            let formats = try await audioTracks[0].load(.formatDescriptions)
            let codec = formats.first.flatMap {
                CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mFormatID
            }
            try require(codec == kAudioFormatMPEG4AAC, "AAC audio codec")
            let duration = try await asset.load(.duration).seconds
            let expected = project.songs[index].end - project.songs[index].start
            try require(abs(duration - expected) < 0.06, "trimmed duration \(duration) vs \(expected)")
            let metadata = try await asset.load(.metadata)
            var strings = [String: String]()
            var binaries = [String: Data]()
            for item in metadata {
                let key = item.identifier?.rawValue ?? "unknown"
                if let value = try await item.load(.stringValue) { strings[key] = value }
                if let value = try await item.load(.dataValue) { binaries[key] = value }
            }
            print(
                "Track \(index + 1): duration=\(duration), tags=\(strings), binary tags=\(binaries.mapValues { $0.count })"
            )
            try require(strings.values.contains(project.songs[index].title), "song title tag")
            try require(strings.values.contains(project.album.title), "album title tag")
            try require(
                strings[AVMetadataIdentifier.iTunesMetadataAlbumArtist.rawValue] == "Test Artist",
                "album artist tag")
            let expectedArtist = index == 0 ? "Test Artist" : "Guest Artist"
            try require(strings.values.contains(expectedArtist), "song artist tag")
            let track = binaries[AVMetadataIdentifier.iTunesMetadataTrackNumber.rawValue]
            try require(
                track != nil && track!.count >= 6 && track![3] == UInt8(index + 1) && track![5] == 2,
                "track number and total")
            let expectedCover = try ArtworkProcessor.exportArtwork(cover, crop: project.artworkCrop).data
            try require(
                binaries.values.contains { $0 == expectedCover },
                "embedded rendered artwork with transparency")
            let exportedCover = NSBitmapImageRep(data: expectedCover)
            try require(
                exportedCover?.pixelsWide == 4 && exportedCover?.pixelsHigh == 4,
                "M4A cover uses the selected zoom crop")
        }
        let document = ProjectDocument()
        document.model.project = project
        document.model.artwork = cover
        document.model.sourceURL = source
        let package = directory.appendingPathComponent("Concert.bootlegger")
        try document.write(to: package, ofType: "nl.theredhead.bootlegger.project")
        try FileManager.default.removeItem(at: source)
        let reopened = ProjectDocument()
        try reopened.read(from: package, ofType: "nl.theredhead.bootlegger.project")
        try require(reopened.model.project == project, "project round trip")
        try require(reopened.model.artwork == cover, "artwork round trip")
        let bundledData = try Data(contentsOf: reopened.model.sourceURL!)
        try require(bundledData == original, "bundled video survives original removal")
        let second = ProjectDocument()
        second.model.project.album.title = "Independent"
        try require(reopened.model.project.album.title == "Test Concert", "independent document state")
        try require(second.model.playback.player !== reopened.model.playback.player, "independent players")
        try require(
            !FileManager.default.fileExists(
                atPath: package.appendingPathComponent(files[0].lastPathComponent).path),
            "exports excluded from bundle")
        if CommandLine.arguments.contains("--keep-fixture") {
            let fixtures = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/Fixtures")
            try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
            let demo = fixtures.appendingPathComponent("Demo-\(UUID().uuidString.prefix(8)).bootlegger")
            try FileManager.default.copyItem(at: package, to: demo)
            print("Demo project: \(demo.path)")
        }
        let broken = directory.appendingPathComponent("Broken.bootlegger")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        var brokenProject = project
        brokenProject.videoFilename = "../Source.mov"
        try JSONEncoder().encode(brokenProject).write(to: broken.appendingPathComponent("Project.json"))
        let brokenDocument = ProjectDocument()
        do {
            try brokenDocument.read(from: broken, ofType: "nl.theredhead.bootlegger.project")
            throw BootleggerError.message("Test failed: external media reference accepted")
        } catch {
            try require(
                error.localizedDescription.contains("invalid media filename"), "reject media outside bundle")
        }
        brokenProject.videoFilename = "Missing.mov"
        try JSONEncoder().encode(brokenProject).write(to: broken.appendingPathComponent("Project.json"))
        do {
            try brokenDocument.read(from: broken, ofType: "nl.theredhead.bootlegger.project")
            throw BootleggerError.message("Test failed: missing media accepted")
        } catch {
            try require(
                error.localizedDescription.contains("recording is missing"), "useful missing-media error")
        }
        brokenProject.version = 99
        try JSONEncoder().encode(brokenProject).write(to: broken.appendingPathComponent("Project.json"))
        do {
            try brokenDocument.read(from: broken, ofType: "nl.theredhead.bootlegger.project")
            throw BootleggerError.message("Test failed: future version accepted")
        } catch {
            try require(
                error.localizedDescription.contains("unsupported format version"),
                "reject unknown project version")
        }
        brokenDocument.close()
        reopened.close()
        second.close()
        document.close()
        print(
            "PASS: timestamps, invalid ranges, overlapping exports, durations, tags, artwork, self-contained project round trip, independent documents, undo/redo, cancellation, bundle validation."
        )
    }

    private static func writeWave(to url: URL) throws {
        let rate = 44100
        let count = rate * 6
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        text("RIFF")
        integer(UInt32(36 + count * 2))
        text("WAVEfmt ")
        integer(UInt32(16))
        integer(UInt16(1))
        integer(UInt16(1))
        integer(UInt32(rate))
        integer(UInt32(rate * 2))
        integer(UInt16(2))
        integer(UInt16(16))
        text("data")
        integer(UInt32(count * 2))
        for sample in 0..<count {
            integer(Int16(sin(Double(sample) * 440 * 2 * .pi / Double(rate)) * 12000))
        }
        try data.write(to: url)
    }
}
