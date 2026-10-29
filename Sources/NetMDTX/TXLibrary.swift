import AVFoundation
import Combine
import Foundation

struct TXQueuedFile: Identifiable {
    let id = UUID()
    let url: URL
    let duration: Double
    var title: String { return url.deletingPathExtension().lastPathComponent }
}

/// Owns the pending import list. The shared controller serializes native device operations.
@MainActor
final class TXLibrary: ObservableObject {
    let controller = NetMDController.shared
    let extraction = TXExtraction()
    @Published var settings = NetMDSettings(defaults: .standard) {
        didSet { settings.save(to: .standard) }
    }
    @Published var convertToWAV = UserDefaults.standard.object(forKey: "tx.convertToWAV") as? Bool ?? true {
        didSet { UserDefaults.standard.set(convertToWAV, forKey: "tx.convertToWAV") }
    }
    @Published private(set) var isImporting = false
    @Published private(set) var isRenaming = false

    var isOccupied: Bool {
        return isRenaming || isImporting || isTransferring || controller.isBusy || extraction.isActive
    }

    func reorder(order: [Int], disc: NetMDDisc) -> Bool {
        guard !isOccupied, disc.writable, order.sorted() == Array(disc.tracks.indices),
            order != Array(disc.tracks.indices)
        else { return false }
        isRenaming = true
        Task {
            defer { isRenaming = false }
            do { try await controller.reorder(order: order, confirmedDisc: disc) } catch {
                self.error = error.localizedDescription
            }
        }
        return true
    }

    func rename(title: String, track: Int?, disc: NetMDDisc) {
        guard !isOccupied, disc.writable else { return }
        guard title.count <= 120 else {
            error = "Use a title of at most 120 characters."
            return
        }
        guard title.rangeOfCharacter(from: .controlCharacters) == nil else {
            error = "Titles cannot contain control characters or line breaks."
            return
        }
        guard track != nil || !title.contains("//") else {
            error = "Album titles cannot contain //, which MiniDisc reserves for track groups."
            return
        }
        isRenaming = true
        Task {
            defer { isRenaming = false }
            do { try await controller.rename(title: title, track: track, confirmedDisc: disc) } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Reserve the drop synchronously so a second drag cannot be accepted and silently discarded.
    func importFiles(_ urls: [URL]) -> Bool {
        guard !isOccupied, controller.disc?.writable == true else { return false }
        totalCount = 0
        completedCount = 0
        isImporting = true
        Task {
            defer { isImporting = false }
            error = nil
            await enqueue(urls)
            if error == nil { await transfer(settings: settings) }
        }
        return true
    }

    @Published private(set) var queue: [TXQueuedFile] = []
    @Published private(set) var isTransferring = false
    @Published var error: String?
    @Published private(set) var totalCount = 0
    @Published private(set) var completedCount = 0
    @Published private(set) var currentFilename = ""
    private var stopping = false

    func overallProgress(trackProgress: Double) -> Double {
        guard totalCount > 0 else { return 0 }
        return min(
            1,
            (Double(completedCount) + (controller.isWriting ? max(0, min(1, trackProgress)) : 0))
                / Double(totalCount))
    }

    func monitorAttachments(onAttach: () -> Void) async {
        var previous: [NetMDDevice] = []
        while !Task.isCancelled {
            await controller.detectDevices()
            let attached = controller.devices
            if !attached.isEmpty && attached != previous {
                await controller.refresh()
                onAttach()
            }
            previous = attached
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
        }
    }

    func enqueue(_ urls: [URL]) async {
        guard !isTransferring else { return }
        do {
            var additions: [TXQueuedFile] = []
            for url in urls {
                let asset = AVURLAsset(url: url)
                guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
                    throw BootleggerError.message("\(url.lastPathComponent) has no supported audio track.")
                }
                let duration = try await asset.load(.duration).seconds
                guard duration.isFinite, duration >= 0.024 else {
                    throw BootleggerError.message("\(url.lastPathComponent) has no valid audio duration.")
                }
                additions.append(TXQueuedFile(url: url, duration: duration))
            }
            queue.append(contentsOf: additions)
        } catch { self.error = error.localizedDescription }
    }

    func remove(_ id: UUID) { queue.removeAll { $0.id == id } }

    func cancel() {
        stopping = true
        controller.cancel()
    }

    func transfer(settings: NetMDSettings) async {
        guard !isTransferring, let disc = controller.disc else { return }
        isTransferring = true
        stopping = false
        totalCount = queue.count
        completedCount = 0
        defer { isTransferring = false }
        do {
            let songs = queue.map { Song(title: $0.title, start: 0, end: $0.duration) }
            // Each dropped file is an independent recording, even with the gapless preference enabled.
            var recording = settings
            recording.gaplessSP = false
            try NetMDPreflight.validate(songs: songs, disc: disc, settings: recording)
            for item in queue {
                if stopping { break }
                guard let current = controller.disc else { break }
                currentFilename = item.title
                var project = Project()
                project.album.title = current.title
                project.songs = [Song(title: item.title, start: 0, end: item.duration)]
                guard
                    await controller.write(
                        project: project, sourceURL: item.url, settings: recording, confirmedDisc: current)
                else { break }
                completedCount += 1
                queue.removeAll { $0.id == item.id }
            }
            if let message = controller.errorMessage {
                error = message
                controller.errorMessage = nil
            }
        } catch { self.error = error.localizedDescription }
    }
}
