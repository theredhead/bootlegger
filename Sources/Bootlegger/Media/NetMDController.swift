import AVFoundation
import Combine
import Foundation

/// One USB owner across all document windows. Cancellation finishes an active USB track safely.
@MainActor
final class NetMDController: ObservableObject {
    static let shared = NetMDController()
    @Published private(set) var devices: [NetMDDevice] = []
    @Published private(set) var disc: NetMDDisc?
    @Published private(set) var isBusy = false
    @Published private(set) var isWriting = false
    @Published private(set) var status = "Connect one NetMD recorder and insert a recordable MD."
    @Published private(set) var progress = 0.0
    @Published var errorMessage: String?
    private var cancelURL: URL?
    private var cancellationRequested = false
    private var isDetectingDevices = false

    var hasAttachedDevice: Bool { return !devices.isEmpty }

    /// Enumeration does not open/reset a recorder or read/change its disc.
    func detectDevices() async {
        guard !isBusy, !isDetectingDevices else { return }
        isDetectingDevices = true
        defer { isDetectingDevices = false }
        do {
            let events = try await NetMDTransport.run(NetMDRequest(command: "devices")) { _ in }
            let attached = events.last?.devices ?? []
            if devices != attached {
                devices = attached
                disc = nil
                status =
                    attached.isEmpty
                    ? "No NetMD recorder attached."
                    : "\(attached[0].name) attached. Refresh to read the inserted disc."
            }
        } catch {
            devices = []
            disc = nil
            status = error.localizedDescription
        }
    }

    func refresh() async {
        guard !isBusy else { return }
        await detectDevices()
        guard hasAttachedDevice, !isBusy else { return }
        isBusy = true
        status = "Reading NetMD recorder…"
        defer { isBusy = false }
        do {
            disc = try await inspect()
            status = "\(disc?.device ?? "NetMD") connected."
        } catch {
            disc = nil
            status = error.localizedDescription
        }
    }

    private func inspect() async throws -> NetMDDisc {
        let events = try await NetMDTransport.run(NetMDRequest(command: "inspect")) { _ in }
        guard let disc = events.last?.disc else {
            throw BootleggerError.message("Could not read the inserted MD.")
        }
        return disc
    }

    func erase(_ confirmedDisc: NetMDDisc) async {
        guard !isBusy else { return }
        isBusy = true
        status = "Erasing MiniDisc… Keep the recorder connected."
        defer { isBusy = false }
        do {
            let events = try await NetMDTransport.run(
                NetMDRequest(command: "erase", fingerprint: confirmedDisc.fingerprint)
            ) { _ in }
            disc = events.last?.disc
            status = "MiniDisc erased. Capacity refreshed."
        } catch {
            disc = nil
            errorMessage = error.localizedDescription
            status = "Erase failed. Refresh the disc before continuing."
        }
    }

    @discardableResult
    func write(project: Project, sourceURL: URL, settings: NetMDSettings, confirmedDisc: NetMDDisc) async
        -> Bool
    {
        guard !isBusy else { return false }
        isBusy = true
        isWriting = true
        progress = 0
        cancellationRequested = false
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("BootleggerMD-\(UUID())")
        cancelURL = staging.appendingPathComponent("cancel")
        defer {
            try? FileManager.default.removeItem(at: staging)
            cancelURL = nil
            isBusy = false
            isWriting = false
        }
        do {
            let current = try await inspect()
            guard current.fingerprint == confirmedDisc.fingerprint else {
                throw BootleggerError.message(
                    "The device or disc changed. Refresh and review the export again.")
            }
            try NetMDPreflight.validate(songs: project.songs, disc: current, settings: settings)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let asset = AVURLAsset(url: sourceURL)
            try AudioExporter.validate(project: project, duration: try await asset.load(.duration).seconds)
            var pcm = FileExportSettings()
            pcm.format = .wav
            pcm.bitDepth = 16
            pcm.sampleRate = 44100
            var tracks: [NetMDRequest.Track] = []
            let totalDuration = project.songs.reduce(0) { $0 + $1.end - $1.start }
            var preparedDuration = 0.0
            let gapless = NetMDPreflight.usesGapless(disc: current, settings: settings)
            if gapless {
                status = "Preparing continuous concert audio…"
                let composition = AVMutableComposition()
                guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first,
                    let destination = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid)
                else {
                    throw BootleggerError.message("Cannot prepare concert audio.")
                }
                var cursor = CMTime.zero
                for song in project.songs {
                    if cancellationRequested { throw CancellationError() }
                    let range = CMTimeRange(
                        start: CMTime(seconds: song.start, preferredTimescale: 44100),
                        end: CMTime(seconds: song.end, preferredTimescale: 44100))
                    try destination.insertTimeRange(range, of: sourceTrack, at: cursor)
                    cursor = cursor + range.duration
                }
                let path = staging.appendingPathComponent("concert.wav")
                try await AudioFileEncoder.write(
                    asset: composition,
                    song: Song(title: project.album.title, start: 0, end: cursor.seconds),
                    destination: path, settings: pcm, metadata: []
                ) { [weak self] fraction in self?.progress = fraction * 0.15 }
                try await NetMDPCMFile.normalize(path)
                tracks = project.songs.map {
                    .init(path: path.path, title: $0.title, duration: $0.end - $0.start)
                }
            } else {
                for (index, song) in project.songs.enumerated() {
                    if cancellationRequested { throw CancellationError() }
                    status = "Preparing \(index + 1)/\(project.songs.count): \(song.title)…"
                    let path = staging.appendingPathComponent("\(index).wav")
                    try await AudioFileEncoder.write(
                        asset: asset, song: song, destination: path,
                        settings: pcm, metadata: []
                    ) { [weak self] fraction in
                        self?.progress =
                            0.15 * (preparedDuration + fraction * (song.end - song.start)) / totalDuration
                    }
                    try await NetMDPCMFile.normalize(path)
                    var prepared = path
                    if settings.encoding == .software {
                        status = "Encoding ATRAC \(index + 1)/\(project.songs.count): \(song.title)…"
                        prepared = try await ATRACEncoder.encode(path, mode: settings.mode)
                    }
                    tracks.append(
                        .init(path: prepared.path, title: song.title, duration: song.end - song.start))
                    preparedDuration += song.end - song.start
                }
            }
            if cancellationRequested { throw CancellationError() }
            let recovery = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Bootlegger/NetMDRecovery/\(UUID())")
            let events = try await NetMDTransport.run(
                NetMDRequest(
                    command: "write", fingerprint: current.fingerprint, title: project.album.title,
                    mode: settings.mode, encoding: settings.encoding,
                    gapless: NetMDPreflight.usesGapless(disc: current, settings: settings),
                    tracks: tracks, cancelPath: cancelURL?.path, recoveryPath: recovery.path)
            ) { [weak self] event in
                if let value = event.progress {
                    self?.progress = max(self?.progress ?? 0, 0.15 + value * 0.85)
                }
                if let message = event.message { self?.status = message }
            }
            if events.last?.type == "cancelled" {
                status = "MD export stopped after the current track. Completed tracks remain on the disc."
            } else {
                progress = 1
                status = "MiniDisc export complete."
            }
            disc = try await inspect()
            return events.last?.type == "complete"
        } catch is CancellationError {
            status = "MD export cancelled before writing."
        } catch {
            disc = nil
            errorMessage = error.localizedDescription
            status = "MD export failed. Completed tracks may remain on the disc; refresh before retrying."
        }
        return false
    }

    func cancel() {
        guard isWriting else { return }
        cancellationRequested = true
        if let cancelURL { try? Data().write(to: cancelURL, options: .atomic) }
        status = "Stopping after the current track finishes… Keep the recorder connected."
    }
}
