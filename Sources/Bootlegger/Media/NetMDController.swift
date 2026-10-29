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

    /// Reads recorded SP audio using the RH1's native upload command, without changing the disc.
    func readSP(track: Int, disc confirmed: NetMDDisc, destination: URL) async throws {
        guard !isBusy else {
            throw BootleggerError.message("The recorder is busy. Try again when it finishes.")
        }
        guard confirmed.supportsNativeSPRead == true,
            confirmed.tracks.indices.contains(track), confirmed.tracks[track].mode == "sp"
        else { throw BootleggerError.message("This recorder and track do not support digital SP playback.") }
        isBusy = true
        progress = 0
        status = "Reading recorded audio from MiniDisc…"
        defer { isBusy = false }
        let events = try await NetMDTransport.run(
            NetMDRequest(
                command: "readSP", fingerprint: confirmed.fingerprint,
                trackIndex: track, outputPath: destination.path)
        ) { [weak self] event in
            if let value = event.progress { self?.progress = value }
            if let text = event.message { self?.status = text }
        }
        guard events.last?.type == "complete" else {
            throw BootleggerError.message("The recorded audio could not be read completely.")
        }
        status = "Recorded audio read successfully."
    }

    func reorder(order: [Int], confirmedDisc: NetMDDisc) async throws {
        guard !isBusy, confirmedDisc.writable else {
            throw BootleggerError.message("The recorder is busy or the MiniDisc is write-protected.")
        }
        guard order.sorted() == Array(confirmedDisc.tracks.indices) else {
            throw BootleggerError.message("The track order is invalid. Refresh the disc.")
        }
        isBusy = true
        status = "Saving track order…"
        defer { isBusy = false }
        do {
            let events = try await NetMDTransport.run(
                NetMDRequest(command: "reorder", fingerprint: confirmedDisc.fingerprint, trackOrder: order)
            ) { _ in }
            guard let updated = events.last?.disc else {
                throw BootleggerError.message("Refresh to read the updated track order.")
            }
            disc = updated
            status = "Track order saved."
        } catch {
            // A failed multi-track move may already have moved some tracks. Read the actual state.
            disc = nil
            disc = try? await inspect()
            throw error
        }
    }

    func rename(title: String, track: Int?, confirmedDisc: NetMDDisc) async throws {
        guard !isBusy else { throw BootleggerError.message("The recorder is busy.") }
        guard confirmedDisc.writable else {
            throw BootleggerError.message("The MiniDisc is write-protected.")
        }
        guard track == nil || confirmedDisc.tracks.indices.contains(track!) else {
            throw BootleggerError.message("The selected track is no longer available.")
        }
        isBusy = true
        status = "Saving title to MiniDisc…"
        defer { isBusy = false }
        let events = try await NetMDTransport.run(
            NetMDRequest(
                command: "rename", fingerprint: confirmedDisc.fingerprint,
                title: title, trackIndex: track)
        ) { _ in }
        guard let updated = events.last?.disc else {
            throw BootleggerError.message("The recorder did not return the updated title. Refresh the disc.")
        }
        disc = updated
        status = "Title saved to MiniDisc."
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
