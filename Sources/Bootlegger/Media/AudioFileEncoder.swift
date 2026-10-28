import AVFoundation

/// Native reader/writer conversion. Container-specific encoding stays behind this adapter.
@MainActor
enum AudioFileEncoder {
    static func write(
        asset: AVAsset, song: Song, destination: URL, settings: FileExportSettings,
        metadata: [AVMetadataItem], progress: (Double) -> Void = { _ in }
    ) async throws {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw BootleggerError.message("The recording has no audio track.")
        }
        let fileType: AVFileType
        switch settings.format {
        case .aac, .appleLossless: fileType = .m4a
        case .wav: fileType = .wav
        case .aiff: fileType = .aiff
        case .caf: fileType = .caf
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: settings.sampleRate,
                AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            ])
        guard reader.canAdd(output) else { throw BootleggerError.message("Cannot decode this recording.") }
        reader.add(output)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: song.start, preferredTimescale: 60000),
            end: CMTime(seconds: song.end, preferredTimescale: 60000))
        let writer = try AVAssetWriter(outputURL: destination, fileType: fileType)
        var encoding: [String: Any] = [AVSampleRateKey: settings.sampleRate, AVNumberOfChannelsKey: 2]
        switch settings.format {
        case .aac:
            encoding[AVFormatIDKey] = kAudioFormatMPEG4AAC
            encoding[AVEncoderBitRateKey] = settings.bitrate * 1000
        case .appleLossless:
            encoding[AVFormatIDKey] = kAudioFormatAppleLossless
            encoding[AVEncoderBitDepthHintKey] = settings.bitDepth
        case .wav, .aiff, .caf:
            encoding[AVFormatIDKey] = kAudioFormatLinearPCM
            encoding[AVLinearPCMBitDepthKey] = settings.bitDepth
            encoding[AVLinearPCMIsFloatKey] = false
            encoding[AVLinearPCMIsBigEndianKey] = settings.format == .aiff
            encoding[AVLinearPCMIsNonInterleaved] = false
        }
        guard writer.canApply(outputSettings: encoding, forMediaType: .audio) else {
            throw BootleggerError.message("macOS cannot encode the selected audio format and settings.")
        }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: encoding)
        guard writer.canAdd(input) else { throw BootleggerError.message("Cannot create the audio encoder.") }
        writer.add(input)
        if settings.format.supportsAlbumMetadata { writer.metadata = metadata }
        var lastProgress = -1.0
        do {
            progress(0)
            guard reader.startReading(), writer.startWriting() else {
                throw reader.error ?? writer.error
                    ?? BootleggerError.message("Cannot start audio conversion.")
            }
            writer.startSession(atSourceTime: reader.timeRange.start)
            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                await Task.yield()
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else {
                        throw writer.error ?? BootleggerError.message("Audio encoder stopped unexpectedly.")
                    }
                    try await Task.sleep(for: .milliseconds(5))
                }
                let duration = CMSampleBufferGetDuration(sample).seconds
                let sampleDuration =
                    duration.isFinite
                    ? duration
                    : Double(CMSampleBufferGetNumSamples(sample)) / Double(settings.sampleRate)
                let position = CMSampleBufferGetPresentationTimeStamp(sample).seconds + sampleDuration
                let fraction = max(0, min(0.99, (position - song.start) / (song.end - song.start)))
                if fraction.isFinite && fraction - lastProgress >= 0.005 {
                    progress(fraction)
                    lastProgress = fraction
                }
                guard input.append(sample) else {
                    throw writer.error ?? BootleggerError.message("Could not write audio samples.")
                }
            }
            guard reader.status == .completed else {
                throw reader.error ?? BootleggerError.message("Audio decoding did not complete.")
            }
            writer.endSession(atSourceTime: reader.timeRange.end)
            input.markAsFinished()
            await writer.finishWriting()
            try Task.checkCancellation()
            guard writer.status == .completed else {
                throw writer.error ?? BootleggerError.message("Audio encoding did not complete.")
            }
            progress(1)
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }
    }
}
