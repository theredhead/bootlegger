import AVFoundation
import CoreVideo
import Foundation

/// Generates a disposable movie with color frames and audio using only native frameworks.
enum MediaFixture {
    static func movie(in directory: URL, audioURL: URL) async throws -> URL {
        let silentURL = directory.appendingPathComponent("Silent.mov")
        let writer = try AVAssetWriter(outputURL: silentURL, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 320,
                AVVideoHeightKey: 180,
            ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 180,
            ])
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? BootleggerError.message("Fixture writer failed")
        }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
                if writer.status == .failed {
                    throw writer.error ?? BootleggerError.message("Fixture writer failed")
                }
            }
            var buffer: CVPixelBuffer?
            guard
                CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32ARGB, nil, &buffer)
                    == kCVReturnSuccess, let buffer
            else {
                throw BootleggerError.message("Fixture pixel buffer failed")
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let bytes = CVPixelBufferGetBaseAddress(buffer) {
                memset(bytes, Int32(frame * 3), CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 10))
            else {
                throw writer.error ?? BootleggerError.message("Fixture frame append failed")
            }
        }
        writer.endSession(atSourceTime: CMTime(seconds: 6, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? BootleggerError.message("Fixture completion failed")
        }
        let composition = AVMutableComposition()
        let silent = AVURLAsset(url: silentURL)
        let audio = AVURLAsset(url: audioURL)
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 6, preferredTimescale: 600))
        let videoTrack = try await silent.loadTracks(withMediaType: .video)[0]
        let audioTrack = try await audio.loadTracks(withMediaType: .audio)[0]
        try composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?.insertTimeRange(
                range, of: videoTrack, at: .zero)
        try composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?.insertTimeRange(
                range, of: audioTrack, at: .zero)
        let result = directory.appendingPathComponent("Source.mov")
        guard
            let exporter = AVAssetExportSession(
                asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else {
            throw BootleggerError.message("Fixture composition export failed")
        }
        try await exporter.export(to: result, as: .mov)
        return result
    }
}
