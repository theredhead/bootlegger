import AppKit
import Combine
import UniformTypeIdentifiers

struct TXPromisedTrack: Sendable {
    let disc: NetMDDisc
    let index: Int
    let convertToWAV: Bool
    var batchID: UUID?

    var filename: String {
        let title = AudioExporter.safeFilename(
            disc.tracks.indices.contains(index) ? disc.tracks[index].title : "Untitled")
        return "\(index + 1)-\(title).\(convertToWAV ? "wav" : "aea")"
    }

    static func supports(_ disc: NetMDDisc, index: Int) -> Bool {
        return disc.supportsNativeSPRead == true && disc.tracks.indices.contains(index)
            && disc.tracks[index].mode == "sp"
    }
}

/// Finder file promises start work only after a drop, serializing all device reads.
@MainActor
final class TXExtraction: NSObject, ObservableObject, NSFilePromiseProviderDelegate {
    @Published private(set) var pendingCount = 0
    @Published private(set) var status = ""
    @Published var error: String?
    @Published private(set) var totalCount = 0
    @Published private(set) var completedCount = 0
    @Published private(set) var currentFilename = ""
    @Published private(set) var hasStarted = false
    @Published private(set) var isDecoding = false
    @Published private(set) var isReading = false
    @Published private(set) var cancelling = false
    private var batchID: UUID?

    var isActive: Bool { return hasStarted && completedCount < totalCount }
    var currentNumber: Int { return min(completedCount + 1, totalCount) }

    func overallProgress(trackProgress: Double) -> Double {
        guard totalCount > 0 else { return 0 }
        let fraction = isDecoding ? 0.95 : isReading ? max(0, min(1, trackProgress)) * 0.9 : 0
        return min(1, (Double(completedCount) + (isActive ? fraction : 0)) / Double(totalCount))
    }

    /// The drag session supplies the full selection before Finder requests individual files.
    func prepareBatch(id: UUID, count: Int) {
        guard !isActive else { return }
        batchID = id
        totalCount = count
        completedCount = 0
        hasStarted = false
        cancelling = false
        isDecoding = false
    }

    func cancel() {
        cancelling = true
        totalCount = completedCount + pendingCount
    }
    private var tail: Task<Void, Never>?
    private let read: @MainActor (Int, NetMDDisc, URL) async throws -> Void

    init(
        read: @escaping @MainActor (Int, NetMDDisc, URL) async throws -> Void = { index, disc, url in
            try await NetMDController.shared.readSP(track: index, disc: disc, destination: url)
        }
    ) {
        self.read = read
        super.init()
    }

    func provider(for track: TXPromisedTrack, row: Int? = nil) -> NSFilePromiseProvider {
        let type = track.convertToWAV ? UTType.wav.identifier : UTType.data.identifier
        let provider = TXTrackFilePromise(fileType: type, delegate: self)
        provider.row = row
        provider.userInfo = track
        return provider
    }

    nonisolated func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        return .main
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String
    ) -> String {
        return (filePromiseProvider.userInfo as? TXPromisedTrack)?.filename ?? "Track.wav"
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let track = filePromiseProvider.userInfo as? TXPromisedTrack
        let completion = TXPromiseCompletion(completionHandler)
        // AppKit invokes writes on the operation queue supplied above.
        MainActor.assumeIsolated {
            guard let track else {
                completion.finish(BootleggerError.message("The dragged track is unavailable."))
                return
            }
            if track.batchID == nil {
                if !isActive { prepareBatch(id: UUID(), count: 0) }
                totalCount += 1
            } else if track.batchID != batchID {
                prepareBatch(id: track.batchID!, count: 1)
            }
            totalCount = max(totalCount, completedCount + pendingCount + 1)
            hasStarted = true
            pendingCount += 1
            let previous = tail
            tail = Task {
                await previous?.value
                defer {
                    isReading = false
                    isDecoding = false
                    completedCount += 1
                    pendingCount -= 1
                }
                currentFilename = track.filename
                isDecoding = false
                do {
                    if cancelling { throw CancellationError() }
                    try await extract(track, to: url)
                    status = "Copied \(track.filename)."
                    completion.finish(nil)
                } catch {
                    if !(error is CancellationError) { self.error = error.localizedDescription }
                    cancelling = true
                    // Finder may abandon promises not yet requested after a failed/cancelled file.
                    totalCount = completedCount + pendingCount
                    status = error is CancellationError ? "Copy cancelled." : "Copy failed."
                    completion.finish(error)
                }
            }
        }
    }

    func extract(_ track: TXPromisedTrack, to destination: URL) async throws {
        guard TXPromisedTrack.supports(track.disc, index: track.index) else {
            throw BootleggerError.message("This recorder or recording format does not support extraction.")
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw BootleggerError.message("A file named \(destination.lastPathComponent) already exists.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NetMDTX-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = directory.appendingPathComponent("track.aea")
        status = "Reading \(track.filename)…"
        isReading = true
        defer { isReading = false }
        try await read(track.index, track.disc, raw)
        let source: URL
        if track.convertToWAV {
            isReading = false
            isDecoding = true
            status = "Decoding \(track.filename)…"
            source = try await ATRACDecoder.decodeSP(raw)
        } else {
            source = raw
        }
        // copyItem refuses replacement, including a file created while the device was reading.
        try FileManager.default.copyItem(at: source, to: destination)
    }
}

/// AppKit supplies this callback without Sendable annotations. Delivery stays on its requested main queue.
private final class TXPromiseCompletion: @unchecked Sendable {
    private let handler: (Error?) -> Void

    init(_ handler: @escaping (Error?) -> Void) { self.handler = handler }

    @MainActor func finish(_ error: Error?) { handler(error) }
}

/// Adds an app-local row identity while retaining Finder's native file-promise representation.
final class TXTrackFilePromise: NSFilePromiseProvider {
    static let rowType = NSPasteboard.PasteboardType("nl.theredhead.NetMDTX.track-row")
    var row: Int?

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        return super.writableTypes(for: pasteboard) + (row == nil ? [] : [Self.rowType])
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard)
        -> NSPasteboard.WritingOptions
    {
        if type == Self.rowType { return [] }
        return super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == Self.rowType { return row.map(String.init) }
        return super.pasteboardPropertyList(forType: type)
    }
}

/// Computes the final permutation from table insertion semantics, retaining selected tracks' order.
enum TXTrackOrder {
    static func moving(_ rows: IndexSet, to insertion: Int, count: Int) -> [Int]? {
        guard !rows.isEmpty, rows.allSatisfy({ (0..<count).contains($0) }),
            (0...count).contains(insertion)
        else { return nil }
        var order = (0..<count).filter { !rows.contains($0) }
        let destination = insertion - rows.filter { $0 < insertion }.count
        order.insert(contentsOf: rows, at: destination)
        return order
    }
}
