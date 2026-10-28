import AVFoundation
import Combine
import Foundation

/// Each document owns one player and removes its periodic observer on teardown.
@MainActor
final class Playback: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var duration = 0.0
    @Published private(set) var position = 0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var hasVideo = false
    private var observer: Any?
    private var statusObservation: AnyCancellable?

    init() {
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.position = max(0, time.seconds.isFinite ? time.seconds : 0)
            }
        }
        statusObservation = player.publisher(for: \.timeControlStatus).sink { [weak self] status in
            self?.isPlaying = status == .playing
        }
    }

    func load(_ url: URL) async throws {
        player.pause()
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else {
            throw BootleggerError.message(
                "macOS cannot play this file. Choose an unprotected audio or video recording in a supported format."
            )
        }
        let loadedDuration = try await asset.load(.duration).seconds
        guard loadedDuration.isFinite, loadedDuration > 0 else {
            throw BootleggerError.message("The selected recording has no usable duration.")
        }
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw BootleggerError.message("The selected file has no audio track.")
        }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        try Task.checkCancellation()
        hasVideo = !videoTracks.isEmpty
        duration = loadedDuration
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        seek(0)
    }

    func seek(_ seconds: Double) {
        let target = min(max(seconds, 0), duration)
        player.currentItem?.forwardPlaybackEndTime = .invalid
        position = target
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 60000), toleranceBefore: .zero,
            toleranceAfter: .zero)
    }

    func clearPreviewEnd() { player.currentItem?.forwardPlaybackEndTime = .invalid }

    func preview(_ song: Song) {
        seek(song.start)
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: song.end, preferredTimescale: 60000)
        player.play()
    }

    func toggle() {
        if isPlaying {
            player.pause()
        } else {
            player.currentItem?.forwardPlaybackEndTime = .invalid
            if position >= duration { seek(0) }
            player.play()
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let observer {
            player.removeTimeObserver(observer)
            self.observer = nil
        }
        statusObservation = nil
    }
}
