import AppKit
import Foundation
import SwiftUI

@MainActor
enum EditingSafetyTests {
    static func run(source: URL) async throws {
        let model = ProjectModel()
        await model.importRecording(from: source)?.value
        defer { model.close() }
        let first = Song(title: "First", start: 1, end: 4)
        let second = Song(title: "Overlapping", start: 3, end: 5)
        model.project.songs = [first, second]
        let binding = model.songBinding(for: first)
        for boundaries in [(2.0, 1.0), (4.0, 4.0), (-1.0, 4.0), (1.0, 7.0), (Double.nan, 4.0)] {
            var candidate = first
            candidate.start = boundaries.0
            candidate.end = boundaries.1
            binding.wrappedValue = candidate
            try SmokeTests.require(
                model.song(id: first.id) == first, "invalid boundary update preserves the old range")
        }
        binding.wrappedValue.start = 0.5
        binding.wrappedValue.end = 3.5
        try SmokeTests.require(
            model.song(id: first.id)?.start == 0.5 && model.song(id: first.id)?.end == 3.5,
            "valid boundary edits apply")
        try SmokeTests.require(
            model.song(id: second.id) == second, "independent overlapping ranges remain supported")
        model.selectSong(first.id)
        model.playback.seek(5)
        model.setSongStart()
        try SmokeTests.require(model.song(id: first.id)?.start == 0.5, "S cannot put start after end")
        model.playback.seek(0)
        model.setSongEnd()
        try SmokeTests.require(model.song(id: first.id)?.end == 3.5, "E cannot put end before start")
        let count = model.project.songs.count
        model.playback.seek(model.playback.duration)
        model.addSong()
        try SmokeTests.require(
            model.project.songs.count == count, "adding at EOF cannot create a zero-length song")

        var legacy = first
        legacy.start = 4
        legacy.end = 2
        model.project.songs = [legacy]
        let legacyBinding = model.songBinding(for: legacy)
        legacyBinding.wrappedValue.title = "Still editable"
        try SmokeTests.require(
            model.project.songs[0].title == "Still editable",
            "legacy invalid ranges do not prevent metadata editing")
        legacyBinding.wrappedValue.start = 1
        try SmokeTests.require(
            model.project.songs[0].hasValidRange(within: model.playback.duration),
            "legacy backwards range can be corrected")
        try pointerFocus(model: model)
        let cases: [(String, String, String?)] = [
            ("THE_CURE__LIVE-1992.mp4", "The Cure Live 1992", "1992"),
            ("pink-floyd.live_at_pompeii_1972.wav", "Pink Floyd Live at Pompeii 1972", "1972"),
            ("AC_DC_LIVE_1991.mp3", "AC DC Live 1991", "1991"),
            ("Paul_McCartney_live_2018.m4a", "Paul McCartney Live 2018", "2018"),
            ("R.E.M._live_2004.flac", "R.E.M. Live 2004", "2004"),
            ("The_1975_live_2024.mp4", "The 1975 Live 2024", "2024"),
            ("show_12345_1812_20240101.wav", "Show 12345 1812 20240101", nil),
        ]
        for (filename, title, year) in cases {
            let url = source.deletingLastPathComponent().appendingPathComponent(filename)
            try SmokeTests.require(
                FilenameMetadata.albumTitle(from: url) == title, "smart filename title: \(filename)")
            try SmokeTests.require(FilenameMetadata.year(from: url) == year, "filename year: \(filename)")
        }
        let named = source.deletingLastPathComponent().appendingPathComponent("THE_CURE__LIVE_1992.mov")
        try FileManager.default.copyItem(at: source, to: named)
        let imported = ProjectModel()
        await imported.importRecording(from: named)?.value
        try SmokeTests.require(
            imported.project.album.title == "The Cure Live 1992" && imported.project.album.year == "1992",
            "import seeds cleaned filename metadata")
        imported.project.album.title = "My Concert"
        imported.project.album.year = "2001"
        await imported.importRecording(from: named, confirmReplacement: { true })?.value
        try SmokeTests.require(
            imported.project.album.title == "My Concert" && imported.project.album.year == "2001",
            "replacement preserves existing album title/year")
        imported.close()
        print(
            "PASS: valid range enforcement, S/E boundaries, EOF guard, filename capitalization/year and metadata preservation."
        )
    }
    private static func pointerFocus(model: ProjectModel) throws {
        let window = ProjectWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.model = model
        let root = FlippedFocusTestView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        let field = NSTextField(string: "Title")
        field.frame = NSRect(x: 30, y: 20, width: 200, height: 24)
        let editor = NSTextView(frame: NSRect(x: 30, y: 70, width: 200, height: 35))
        let label = NSTextField(labelWithString: "Playback area")
        label.frame = NSRect(x: 30, y: 200, width: 200, height: 24)
        root.addSubview(field)
        root.addSubview(editor)
        root.addSubview(label)
        window.contentView = root
        window.makeFirstResponder(editor)
        window.handlePointerClick(at: field.convert(NSPoint(x: 10, y: 10), to: nil))
        try SmokeTests.require(
            window.isEditingText, "clicking another editable field does not steal text focus")
        window.handlePointerClick(at: label.convert(NSPoint(x: 10, y: 10), to: nil))
        try SmokeTests.require(
            !window.isEditingText, "clicking a label or playback area restores transport focus")
        window.close()
    }
}

@MainActor
private final class FlippedFocusTestView: NSView {
    override var isFlipped: Bool { return true }
}
