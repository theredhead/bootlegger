import AVFoundation
import AppKit

@MainActor
enum FileExportTests {
    static func run(source: URL, directory: URL) async throws {
        var project = Project()
        project.album.title = "Concert"
        project.album.artist = "Band"
        project.album.year = "2026"
        project.songs = [Song(title: "Opening", start: 0.5, end: 1.75)]
        var settings = FileExportSettings()
        let initialNames = try settings.filenames(project: project)
        try SmokeTests.require(
            initialNames == ["01-Opening.m4a"],
            "default token filename")
        settings.filenameTemplate = "<year> <album artist> - <track #> <track name>"
        let customNames = try settings.filenames(project: project)
        try SmokeTests.require(
            customNames == ["2026 Band - 01 Opening.m4a"],
            "literal and token filename expansion")
        settings.filenameTemplate = "../<track name>"
        let safeNames = try settings.filenames(project: project)
        try SmokeTests.require(
            !safeNames[0].contains("/"),
            "filename tokens cannot create paths")
        settings.filenameTemplate = "same"
        var duplicates = project
        duplicates.songs.append(Song(title: "Other", start: 2, end: 3))
        do {
            _ = try settings.filenames(project: duplicates)
            throw BootleggerError.message("Test failed: duplicate export names accepted")
        } catch let error as BootleggerError {
            try SmokeTests.require(
                error.localizedDescription.contains("duplicate"), "duplicate names rejected")
        }
        let suite = "BootleggerExportTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("appleLossless", forKey: FileExportSettings.formatKey)
        defaults.set(24, forKey: FileExportSettings.bitDepthKey)
        defaults.set("<artist>-<track #>", forKey: FileExportSettings.filenameKey)
        let loaded = FileExportSettings(defaults: defaults)
        try SmokeTests.require(
            loaded.format == .appleLossless && loaded.bitDepth == 24
                && loaded.filenameTemplate == "<artist>-<track #>", "strategy preferences load")
        let field = NSTokenField()
        let coordinator = FilenameFormatField.Coordinator(template: .constant(""))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("<track #>-<track name>", forType: .string)
        let pieces = coordinator.tokenField(field, readFrom: pasteboard) as? [String]
        try SmokeTests.require(
            pieces == ["<track #>", "-", "<track name>"], "dropped tokens preserve separators")
        try SmokeTests.require(
            coordinator.tokenField(field, styleForRepresentedObject: "<track #>") == .rounded
                && coordinator.tokenField(field, styleForRepresentedObject: "-") == .none,
            "field renders token pills and literal text")
        for format in AudioFileFormat.allCases {
            settings = FileExportSettings()
            settings.format = format
            settings.bitDepth = 24
            settings.sampleRate = 48000
            let output = try await AudioExporter.export(
                project: project, artwork: nil,
                sourceURL: source, destination: directory, settings: settings
            ) { _, _ in }
            let file = output.appendingPathComponent("01-Opening.\(format.filenameExtension)")
            let asset = AVURLAsset(url: file)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            let descriptions = try await tracks[0].load(.formatDescriptions)
            let description = CMAudioFormatDescriptionGetStreamBasicDescription(descriptions[0])!.pointee
            let expected: AudioFormatID =
                format == .aac
                ? kAudioFormatMPEG4AAC
                : format == .appleLossless ? kAudioFormatAppleLossless : kAudioFormatLinearPCM
            try SmokeTests.require(
                description.mFormatID == expected && description.mSampleRate == 48000,
                "selected codec and sample rate for \(format)")
            let duration = try await asset.load(.duration).seconds
            try SmokeTests.require(
                abs(duration - 1.25) < 0.06, "precise trimmed duration for \(format): \(duration)")
            if format.supportsAlbumMetadata {
                let tags = try await asset.load(.metadata)
                let titles = AVMetadataItem.metadataItems(
                    from: tags, filteredByIdentifier: .commonIdentifierTitle)
                let title = try await titles.first?.load(.stringValue)
                try SmokeTests.require(title == "Opening", "album metadata for \(format)")
            } else {
                try SmokeTests.require(description.mBitsPerChannel == 24, "24-bit PCM for \(format)")
            }
        }
        print(
            "PASS: all file codecs, trimming, sample rate, bit depth, tags, filename templates, duplicate guards and token clipboard."
        )
    }
}
