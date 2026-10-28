import AVFoundation
import AppKit
import Foundation

@MainActor
enum AudioRecordingTests {
    static func run(audio: URL) async throws {
        let directory = audio.deletingLastPathComponent().appendingPathComponent("AudioOnlyTests")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = directory.appendingPathComponent("Concert.wav")
        try FileManager.default.copyItem(at: audio, to: original)
        let originalBytes = try Data(contentsOf: original)
        for name in ["recording.mp3", "recording.m4a", "recording.wav", "recording.aiff", "recording.flac"] {
            try SmokeTests.require(
                ProjectModel.isRecording(directory.appendingPathComponent(name)),
                "audio extension accepted: \(name)")
        }
        try SmokeTests.require(
            !ProjectModel.isRecording(directory.appendingPathComponent("notes.txt")),
            "non-media drops rejected")
        let document = ProjectDocument()
        await document.model.importRecording(from: original)?.value
        try SmokeTests.require(
            document.model.sourceURL != nil && document.model.errorMessage == nil,
            "audio-only import succeeds")
        try SmokeTests.require(
            !document.model.playback.hasVideo && document.model.playback.duration == 6,
            "audio-only playback has duration and no video")
        document.model.project.album = Album(title: "Audio Concert", artist: "Audio Artist")
        document.model.project.songs = [Song(title: "First", start: 0.5, end: 2.5)]
        document.model.selectedSongID = document.model.project.songs[0].id
        document.model.playback.seek(0.75)
        document.model.setSongStart()
        try SmokeTests.require(
            document.model.project.songs[0].start == 0.75, "audio-only recording supports marking")
        let coverItem = NSMenuItem(
            title: "Capture Frame", action: #selector(ProjectDocument.captureArtworkFromMenu(_:)),
            keyEquivalent: "")
        try SmokeTests.require(
            !document.validateMenuItem(coverItem), "frame capture disabled for audio-only sources")
        let folder = try await AudioExporter.export(
            project: document.model.project, artwork: nil, sourceURL: document.model.sourceURL!,
            destination: directory
        ) { _, _ in }
        let output = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)[
            0]
        let exported = AVURLAsset(url: output)
        let duration = try await exported.load(.duration).seconds
        try SmokeTests.require(abs(duration - 1.75) < 0.06, "audio-only export is correctly trimmed")
        let levels = AudioLevels()
        await levels.prescan(url: document.model.sourceURL!, duration: document.model.playback.duration)?
            .value
        try SmokeTests.require(
            levels.hasFullCache && (levels.samples?.peak(from: 1, to: 2) ?? 0) > 0,
            "audio-only prescan populates measured levels")
        levels.reset()
        let projectURL = directory.appendingPathComponent("Audio Concert.bootlegger")
        try document.write(to: projectURL, ofType: "nl.theredhead.bootlegger.project")
        try FileManager.default.removeItem(at: original)
        let reopened = ProjectDocument()
        try reopened.read(from: projectURL, ofType: "nl.theredhead.bootlegger.project")
        let storedBytes = try Data(contentsOf: reopened.model.sourceURL!)
        try SmokeTests.require(storedBytes == originalBytes, "audio source is bundled without changes")
        try SmokeTests.require(
            reopened.model.project.songs == document.model.project.songs,
            "audio project ranges survive reopening")
        reopened.close()
        document.close()
        print(
            "PASS: audio-only import, marking, frame-capture exclusion, export, prescan, self-contained save/reopen."
        )
    }
}
