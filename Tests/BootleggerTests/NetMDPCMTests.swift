import AVFoundation
import Foundation

@MainActor
enum NetMDPCMTests {
    static func run(source: URL, directory: URL) async throws {
        let path = directory.appendingPathComponent("NetMD-prepared.wav")
        var settings = FileExportSettings()
        settings.format = .wav
        var encodingProgress: [Double] = []
        try await AudioFileEncoder.write(
            asset: AVURLAsset(url: source),
            song: Song(title: "PCM test", start: 0.5, end: 1.5), destination: path, settings: settings,
            metadata: [], progress: { encodingProgress.append($0) })
        try SmokeTests.require(
            encodingProgress.count > 3 && encodingProgress.first == 0 && encodingProgress.last == 1
                && zip(encodingProgress, encodingProgress.dropFirst()).allSatisfy { $0.0 <= $0.1 },
            "audio preparation reports granular monotonic progress through completion")
        let original = try Data(contentsOf: path)
        let samples = audioData(original)
        try await NetMDPCMFile.normalize(path)
        let canonical = try Data(contentsOf: path)
        try SmokeTests.require(
            String(decoding: canonical[12..<16], as: UTF8.self) == "fmt "
                && canonical[20] == 1 && canonical[21] == 0,
            "NetMD WAV begins with a classic integer PCM format chunk")
        try SmokeTests.require(
            String(decoding: canonical[36..<40], as: UTF8.self) == "data"
                && canonical.dropFirst(44) == samples,
            "WAV normalization preserves every PCM byte while removing padding")
        let asset = AVURLAsset(url: path)
        let duration = try await asset.load(.duration).seconds
        try SmokeTests.require(abs(duration - 1) < 0.001, "normalized WAV duration is unchanged")
        for mode in NetMDMode.allCases {
            let encoded = try await ATRACEncoder.encode(path, mode: mode)
            let data = try Data(contentsOf: encoded)
            if mode == .sp {
                let decoded = try await ATRACDecoder.decodeSP(encoded)
                let decodedAsset = AVURLAsset(url: decoded)
                let decodedDuration = try await decodedAsset.load(.duration).seconds
                try SmokeTests.require(
                    abs(decodedDuration - 1) < 0.1, "recorded SP playback decoder preserves duration")
                try SmokeTests.require(
                    data.count > 2048 && data[1] == 8 && data[264] == 2,
                    "software SP produces stereo ATRAC1 AEA")
            } else {
                let block = Int(data[32]) | Int(data[33]) << 8
                try SmokeTests.require(
                    String(decoding: data[12..<16], as: UTF8.self) == "fmt "
                        && data[20] == 0x70 && data[21] == 2
                        && block == (mode == .lp2 ? 384 : 192)
                        && data.count < canonical.count / 4,
                    "software LP produces compact NetMD-compatible ATRAC3 RIFF")
            }
        }
        let once = canonical
        try await NetMDPCMFile.normalize(path)
        let twice = try Data(contentsOf: path)
        try SmokeTests.require(twice == once, "canonical WAV normalization is idempotent")
        let invalid = directory.appendingPathComponent("NetMD-corrupt.wav")
        let bad = Data("RIFF\0\0\0\0WAVE".utf8)
        try bad.write(to: invalid)
        do {
            try await NetMDPCMFile.normalize(invalid)
            throw BootleggerError.message("Test failed: invalid PCM accepted")
        } catch {
            let after = try Data(contentsOf: invalid)
            try SmokeTests.require(after == bad, "invalid preparation never replaces input")
        }
        print(
            "PASS: macOS extensible/padded WAV is normalized losslessly for NetMD, with preserved duration and safe rejection."
        )
    }

    private static func audioData(_ data: Data) -> Data {
        var cursor = 12
        while cursor + 8 <= data.count {
            var size = 0
            for byte in 0..<4 { size |= Int(data[cursor + 4 + byte]) << (8 * byte) }
            if String(decoding: data[cursor..<cursor + 4], as: UTF8.self) == "data" {
                return data.subdata(in: cursor + 8..<cursor + 8 + size)
            }
            cursor += 8 + size + size % 2
        }
        return Data()
    }
}
