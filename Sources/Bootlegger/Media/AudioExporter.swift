import AVFoundation
import Foundation

/// Exports into a fresh album directory; partial output is removed on failure or cancellation.
@MainActor
enum AudioExporter {
    static func validate(project: Project, duration: Double) throws {
        guard !project.album.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !project.album.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw BootleggerError.message("Enter an album title and album artist before exporting.")
        }
        guard !project.songs.isEmpty else {
            throw BootleggerError.message("Add at least one song to export.")
        }
        guard project.songs.count <= 65535 else {
            throw BootleggerError.message("An album cannot contain more than 65,535 tracks.")
        }
        for (index, song) in project.songs.enumerated() {
            guard !song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BootleggerError.message("Track \(index + 1) needs a title.")
            }
            guard song.start.isFinite, song.end.isFinite, song.start >= 0,
                song.end > song.start, song.end <= duration + 0.001
            else {
                throw BootleggerError.message(
                    "Track \(index + 1) has an invalid range. Start must be before end, and both must be within the recording."
                )
            }
        }
    }

    static func export(
        project: Project, artwork: Data?, sourceURL: URL, destination: URL,
        settings: FileExportSettings = FileExportSettings(),
        progress: (Double, String) -> Void
    ) async throws -> URL {
        var ancestor = destination.resolvingSymlinksInPath()
        while ancestor.path != "/" {
            guard ancestor.pathExtension.lowercased() != "bootlegger" else {
                throw BootleggerError.message("Choose an export folder outside the project bundle.")
            }
            ancestor.deleteLastPathComponent()
        }
        let asset = AVURLAsset(url: sourceURL)
        try validate(project: project, duration: try await asset.load(.duration).seconds)
        let filenames = try settings.filenames(project: project)
        let exportedArtwork = try artwork.map {
            try ArtworkProcessor.exportArtwork($0, crop: project.artworkCrop)
        }
        let albumDirectory = destination.appendingPathComponent(
            "\(safeFilename(project.album.title)) — \(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: albumDirectory, withIntermediateDirectories: false)
        do {
            for (index, song) in project.songs.enumerated() {
                try Task.checkCancellation()
                progress(
                    Double(index) / Double(project.songs.count),
                    "Exporting \(index + 1)/\(project.songs.count): \(song.title)…")
                try await AudioFileEncoder.write(
                    asset: asset, song: song,
                    destination: albumDirectory.appendingPathComponent(filenames[index]), settings: settings,
                    metadata: metadata(project: project, song: song, index: index, artwork: exportedArtwork))
                try Task.checkCancellation()
            }
            progress(1, "Export complete.")
            return albumDirectory
        } catch {
            do { try FileManager.default.removeItem(at: albumDirectory) } catch {
                throw BootleggerError.message(
                    "Export failed and partial output could not be removed at \(albumDirectory.path): \(error.localizedDescription)"
                )
            }
            throw error
        }
    }

    static func metadata(project: Project, song: Song, index: Int, artwork: EncodedArtwork?)
        -> [AVMetadataItem]
    {
        var items = [AVMetadataItem]()
        func add(
            _ identifier: AVMetadataIdentifier, _ value: any NSCopying & NSObjectProtocol,
            dataType: String? = nil
        ) {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value
            item.dataType = dataType
            items.append(item)
        }
        add(.commonIdentifierTitle, song.title as NSString)
        add(.commonIdentifierAlbumName, project.album.title as NSString)
        add(.commonIdentifierArtist, (song.artist.isEmpty ? project.album.artist : song.artist) as NSString)
        add(.iTunesMetadataAlbumArtist, project.album.artist as NSString)
        let number = UInt16(index + 1)
        let total = UInt16(project.songs.count)
        let track = Data([
            0, 0, UInt8(number >> 8), UInt8(number & 255), UInt8(total >> 8), UInt8(total & 255), 0, 0,
        ])
        add(.iTunesMetadataTrackNumber, track as NSData, dataType: kCMMetadataBaseDataType_RawData as String)
        if !project.album.genre.isEmpty { add(.iTunesMetadataUserGenre, project.album.genre as NSString) }
        if !project.album.year.isEmpty { add(.iTunesMetadataReleaseDate, project.album.year as NSString) }
        if !project.album.venue.isEmpty {
            add(.iTunesMetadataUserComment, "Venue: \(project.album.venue)" as NSString)
        }
        if let artwork {
            add(
                .commonIdentifierArtwork, artwork.data as NSData,
                dataType: (artwork.isPNG ? kCMMetadataBaseDataType_PNG : kCMMetadataBaseDataType_JPEG)
                    as String)
        }
        return items
    }

    static func safeFilename(_ text: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let sanitized = text.components(separatedBy: forbidden).joined(separator: "-").trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty, sanitized != ".", sanitized != ".." else { return "Untitled" }
        var filename = ""
        for character in sanitized {
            let part = String(character)
            if filename.utf8.count + part.utf8.count > 180 { break }
            filename += part
        }
        return filename.isEmpty ? "Untitled" : filename
    }
}
