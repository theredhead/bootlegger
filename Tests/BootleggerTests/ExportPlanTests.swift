import Foundation

@MainActor
enum ExportPlanTests {
    static func run() throws {
        try SmokeTests.require(
            ExportPlan.durationLabel(59.01) == "01:00"
                && ExportPlan.durationLabel(60) == "01:00"
                && ExportPlan.durationLabel(3599.1) == "1:00:00"
                && ExportPlan.durationLabel(0) == "00:00",
            "export durations round up to whole seconds across minute and hour boundaries")
        try SmokeTests.require(
            !ExportStrategy.available(netMDAttached: false).contains(.miniDisc)
                && ExportStrategy.preferred(netMDAttached: false) == .files,
            "MD is absent from the menu without an attached recorder")
        try SmokeTests.require(
            ExportStrategy.available(netMDAttached: true).contains(.miniDisc)
                && ExportStrategy.preferred(netMDAttached: true) == .miniDisc,
            "attached recorder reveals MD and makes it the default")
        let first = Song(title: "First", start: 0, end: 10)
        let second = Song(title: "Second", start: 5, end: 25)
        let third = Song(title: "Third", start: 30, end: 35)
        var project = Project()
        project.album.title = "Album"
        project.album.artist = "Artist"
        project.songs = [first, second, third]
        var plan = ExportPlan(songs: project.songs)
        try SmokeTests.require(
            plan.selectedSongs == project.songs && plan.duration == 35,
            "export starts with all tracks and sums overlapping durations independently")
        plan.selectedIDs.remove(second.id)
        plan.songs = [third, second, first]
        let snapshot = plan.project(from: project)
        try SmokeTests.require(
            snapshot.songs == [third, first] && plan.duration == 15,
            "export snapshot respects selection and custom order")
        try SmokeTests.require(
            project.songs == [first, second, third] && snapshot.album == project.album,
            "export planning preserves project order and metadata")
        plan.selectedIDs.removeAll()
        try SmokeTests.require(
            plan.duration == 0 && plan.selectedSongs.isEmpty, "empty selection totals zero")
        let model = ProjectModel()
        model.project = project
        model.sourceURL = URL(fileURLWithPath: "/tmp/example.mov")
        model.exportAudio()
        try SmokeTests.require(
            model.isPreparingExport && !model.isExporting && !model.isBusy,
            "export command opens preparation without starting output")
        model.close()
        print("PASS: export selection, ordered snapshots, duration totals and preparation routing.")
    }
}
