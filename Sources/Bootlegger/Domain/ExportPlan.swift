import Foundation

enum ExportStrategy: String, CaseIterable, Identifiable {
    case files
    case miniDisc
    case compactDisc

    static func available(netMDAttached: Bool) -> [ExportStrategy] {
        return allCases.filter { $0 != .miniDisc || netMDAttached }
    }

    static func preferred(netMDAttached: Bool) -> ExportStrategy {
        return netMDAttached ? .miniDisc : .files
    }

    var id: String { return rawValue }
    var title: String {
        switch self {
        case .files: return "Export to Files"
        case .miniDisc: return "Write to MD"
        case .compactDisc: return "Write to CD"
        }
    }
}

/// Export order and inclusion are temporary choices, independent of the saved project.
struct ExportPlan {
    var songs: [Song]
    var selectedIDs: Set<UUID>

    init(songs: [Song]) {
        self.songs = songs
        selectedIDs = Set(songs.map(\.id))
    }

    var selectedSongs: [Song] { return songs.filter { selectedIDs.contains($0.id) } }
    var duration: Double { return selectedSongs.reduce(0) { $0 + max(0, $1.end - $1.start) } }

    static func durationLabel(_ seconds: Double) -> String {
        let timestamp = Timestamp.string(ceil(seconds))
        return String(timestamp.dropLast(4))
    }

    func project(from original: Project) -> Project {
        var result = original
        result.songs = selectedSongs
        return result
    }
}
