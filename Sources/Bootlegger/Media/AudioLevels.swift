import AVFoundation
import Combine
import Foundation

struct AudioLevelSamples: Sendable {
    let start: Double
    let interval: Double
    let peaks: [Float]

    var end: Double { return start + Double(peaks.count) * interval }

    func peak(from lower: Double, to upper: Double) -> Float {
        guard upper > start, lower < end, upper > lower else { return 0 }
        let first = max(0, Int(floor((lower - start) / interval)))
        let last = min(peaks.count, max(first + 1, Int(ceil((upper - start) / interval))))
        guard first < last, first < peaks.count else { return 0 }
        return peaks[first..<last].max() ?? 0
    }
}

/// Reads only a bounded neighborhood; a long concert never needs a full waveform scan.
@MainActor
final class AudioLevels: ObservableObject {
    @Published private(set) var samples: AudioLevelSamples?
    @Published private(set) var error: String?
    @Published private(set) var isPrescanning = false
    @Published private(set) var prescanProgress = 0.0
    @Published private(set) var hasFullCache = false
    private var task: Task<Void, Never>?
    private var prescanTask: Task<Void, Never>?
    private var source: URL?
    private var generation = UUID()
    private var pendingRange: ClosedRange<Double>?

    func request(url: URL, position: Double, duration: Double) {
        let lower = max(0, position - 5)
        let upper = min(duration, position + 5)
        if source == url {
            if let samples, samples.start <= lower, samples.end >= upper - 0.002 { return }
            if let pendingRange, pendingRange.lowerBound <= lower, pendingRange.upperBound >= upper { return }
        } else {
            reset()
        }
        task?.cancel()
        source = url
        let start = max(0, position - 15)
        let end = min(duration, position + 15)
        pendingRange = start...max(start, end)
        error = nil
        task = Task {
            do {
                let worker = Task.detached(priority: .utility) {
                    try await Self.read(url: url, start: start, end: end)
                }
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                samples = result
                pendingRange = nil
            } catch is CancellationError {
                // A newer cursor neighborhood owns the current request.
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                pendingRange = nil
            }
        }
    }

    /// One explicit action fills the entire document's in-memory audio cache.
    @discardableResult
    func prescan(url: URL, duration: Double) -> Task<Void, Never>? {
        guard !isPrescanning, duration > 0, duration.isFinite else { return nil }
        if source != url {
            reset()
            source = url
        }
        isPrescanning = true
        prescanProgress = 0
        error = nil
        let scanGeneration = generation
        prescanTask = Task {
            do {
                let levels = self
                let worker = Task.detached(priority: .utility) {
                    try await Self.read(url: url, start: 0, end: duration) { progress in
                        Task { @MainActor in
                            guard levels.generation == scanGeneration, levels.isPrescanning else { return }
                            levels.prescanProgress = progress
                        }
                    }
                }
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                task?.cancel()
                task = nil
                pendingRange = nil
                samples = result
                hasFullCache = true
                prescanProgress = 1
            } catch is CancellationError {
                // Keep any existing cursor cache when the optional prescan is cancelled.
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            guard generation == scanGeneration else { return }
            isPrescanning = false
            prescanTask = nil
        }
        return prescanTask
    }

    func cancelPrescan() { prescanTask?.cancel() }

    /// Saving moves identical media from staging into the bundle without invalidating its levels.
    func relocateSource(to url: URL) { source = url }

    func reset() {
        generation = UUID()
        task?.cancel()
        prescanTask?.cancel()
        task = nil
        prescanTask = nil
        isPrescanning = false
        hasFullCache = false
        prescanProgress = 0
        source = nil
        pendingRange = nil
        samples = nil
        error = nil
    }

    nonisolated static func read(
        url: URL, start: Double, end: Double,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> AudioLevelSamples {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw BootleggerError.message("No audio is available for the level display.")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey: 48000,
            ])
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 48000),
            end: CMTime(seconds: end, preferredTimescale: 48000))
        guard reader.canAdd(output) else {
            throw BootleggerError.message("Audio levels cannot be decoded for this video.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? BootleggerError.message("Audio reading failed.")
        }
        defer { reader.cancelReading() }
        let interval = 0.001
        var peaks = [Float](repeating: 0, count: max(1, Int(ceil((end - start) / interval))))
        var reportedProgress = 0.0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let size = CMBlockBufferGetDataLength(block)
            guard size > 0 else { continue }
            var bytes = Data(count: size)
            let result = bytes.withUnsafeMutableBytes { buffer in
                CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: size, destination: buffer.baseAddress!)
            }
            guard result == kCMBlockBufferNoErr else {
                throw BootleggerError.message("Audio samples could not be read.")
            }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard timestamp.isFinite else {
                throw BootleggerError.message("The audio contains an invalid timestamp.")
            }
            guard let description = CMSampleBufferGetFormatDescription(sample),
                let format = CMAudioFormatDescriptionGetStreamBasicDescription(description),
                format.pointee.mChannelsPerFrame > 0, format.pointee.mSampleRate > 0
            else {
                throw BootleggerError.message("The decoded audio format is invalid.")
            }
            let channels = Int(format.pointee.mChannelsPerFrame)
            let sampleRate = format.pointee.mSampleRate
            let fraction = min(1, max(0, (timestamp - start) / max(end - start, 0.001)))
            if fraction - reportedProgress >= 0.005 {
                progress(fraction)
                reportedProgress = fraction
            }
            bytes.withUnsafeBytes { buffer in
                let values = buffer.bindMemory(to: Float.self)
                for (index, value) in values.enumerated() {
                    let bin = Int(
                        floor((timestamp + Double(index / channels) / sampleRate - start) / interval))
                    if peaks.indices.contains(bin), value.isFinite {
                        peaks[bin] = max(peaks[bin], min(1, abs(value)))
                    }
                }
            }
        }
        if reader.status == .failed {
            throw reader.error ?? BootleggerError.message("Audio decoding failed.")
        }
        try Task.checkCancellation()
        progress(1)
        return AudioLevelSamples(start: start, interval: interval, peaks: peaks)
    }
}
