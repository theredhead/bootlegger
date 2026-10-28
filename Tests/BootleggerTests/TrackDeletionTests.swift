import AppKit
import SwiftUI

@MainActor
enum TrackDeletionTests {
    static func run() async throws {
        for deletedIndex in 0..<3 {
            let model = ProjectModel()
            let songs = (0..<3).map { Song(title: "Song \($0)", start: Double($0), end: Double($0 + 1)) }
            model.project.songs = songs
            model.selectSong(songs[deletedIndex].id)
            let removedBinding = model.songBinding(for: songs[deletedIndex])
            let survivor = songs.first { $0.id != songs[deletedIndex].id }!
            let survivorBinding = model.songBinding(for: survivor)
            model.removeSong(id: songs[deletedIndex].id)
            try SmokeTests.require(
                model.project.songs.count == 2 && model.selectedSong != nil,
                "deleting first/middle/last keeps a valid selection")
            try SmokeTests.require(
                removedBinding.wrappedValue.id == songs[deletedIndex].id,
                "removed row can finish rendering without an array index")
            removedBinding.wrappedValue.title = "Late field commit"
            try SmokeTests.require(
                !model.project.songs.contains { $0.title == "Late field commit" },
                "late edits to removed rows are ignored")
            survivorBinding.wrappedValue.title = "Still this song"
            try SmokeTests.require(
                model.song(id: survivor.id)?.title == "Still this song",
                "remaining bindings resolve identity after indexes shift")
            let count = model.project.songs.count
            model.removeSong(id: songs[deletedIndex].id)
            try SmokeTests.require(model.project.songs.count == count, "repeated deletion is harmless")
            model.close()
        }
        let model = ProjectModel()
        let first = Song(title: "First", start: 0, end: 1)
        let second = Song(title: "Second", start: 1, end: 2)
        model.project.songs = [first, second]
        let binding = model.songBinding(for: first)
        model.moveSong(first.id, offset: 1)
        binding.wrappedValue.artist = "Correct artist"
        try SmokeTests.require(
            model.project.songs[1].id == first.id && model.project.songs[1].artist == "Correct artist"
                && model.project.songs[0].artist.isEmpty, "reordered bindings never edit a different song")
        model.close()

        let document = ProjectDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        document.undoManager = undo
        undo.beginUndoGrouping()
        document.model.project.songs = [first]
        undo.endUndoGrouping()
        undo.removeAllActions()
        let lastBinding = document.model.songBinding(for: first)
        undo.beginUndoGrouping()
        document.model.removeSong(id: first.id)
        undo.endUndoGrouping()
        try SmokeTests.require(
            document.model.project.songs.isEmpty && document.model.selectedSong == nil,
            "deleting the only song clears selection")
        _ = lastBinding.wrappedValue.end
        undo.undo()
        try SmokeTests.require(
            document.model.project.songs == [first] && document.model.selectedSong?.id == first.id,
            "undo restores the final song and selection")
        undo.redo()
        try SmokeTests.require(
            document.model.project.songs.isEmpty && document.model.selectedSong == nil,
            "redo safely removes the final song")
        _ = lastBinding.wrappedValue.start
        document.close()

        // Exercise SwiftUI reconciliation with the actual list, timeline and graph in an invisible window.
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 500), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hostedModel = ProjectModel()
        hostedModel.project.songs = [first, second]
        let host = NSHostingView(
            rootView: VStack {
                SongList(model: hostedModel, playback: hostedModel.playback)
                TimelineView(model: hostedModel, playback: hostedModel.playback)
                AudioLevelView(
                    model: hostedModel, playback: hostedModel.playback, levels: hostedModel.audioLevels)
            })
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        for id in [second.id, first.id] {
            hostedModel.selectSong(id)
            hostedModel.removeSong(id: id)
            await Task.yield()
            host.layoutSubtreeIfNeeded()
        }
        try SmokeTests.require(
            hostedModel.project.songs.isEmpty, "visible row structure reconciles down to no songs")
        window.close()
        hostedModel.close()
        print(
            "PASS: first/middle/last/only track deletion, stale field bindings, reordering, undo/redo and hosted view reconciliation."
        )
    }
}
