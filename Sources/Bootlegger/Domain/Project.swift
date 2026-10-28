import Foundation

struct Song: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var artist = ""
    var start: Double
    var end: Double

    func hasValidRange(within duration: Double? = nil) -> Bool {
        guard start.isFinite, end.isFinite, start >= 0, end > start else { return false }
        if let duration { return end <= duration }
        return true
    }
}

struct Album: Codable, Equatable {
    var title = ""
    var artist = ""
    var year = ""
    var venue = ""
    var genre = "Live"
}

struct Project: Codable, Equatable {
    var version = 1
    // Historical JSON key retained for compatibility; the source can be audio or video.
    var videoFilename: String?
    var album = Album()
    var songs: [Song] = []
    var artworkFilename: String?
    var artworkCrop: ArtworkCrop?
}

/// Converts editable timestamps to seconds without rounding the saved ranges.
enum Timestamp {
    static func string(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds <= Double(Int.max / 1000 - 1) else {
            return "00:00.000"
        }
        let milliseconds = Int((seconds * 1000).rounded())
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds / 60_000) % 60
        let remainder = Double(milliseconds % 60_000) / 1000
        if hours > 0 {
            return "\(hours):" + String(format: "%02d:%06.3f", minutes, remainder)
        }
        return String(format: "%02d:%06.3f", minutes, remainder)
    }

    static func seconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(
            separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            guard let value = Double(part), value.isFinite, value >= 0 else { return nil }
            if index > 0 && value >= 60 { return nil }
            if index < parts.count - 1 && value.rounded() != value { return nil }
            total = total * 60 + value
            guard total.isFinite, total <= Double(Int.max / 1000 - 1) else { return nil }
        }
        return total
    }
}

enum BootleggerError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}
