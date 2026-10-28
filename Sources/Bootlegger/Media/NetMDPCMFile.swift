import Foundation

/// Rewraps macOS WAV output as classic PCM RIFF for netmd++ without altering audio samples.
enum NetMDPCMFile {
    static func normalize(_ url: URL) async throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let fileSize = try input.seekToEnd()
        try input.seek(toOffset: 0)
        let riff = try read(input, count: 12)
        guard String(decoding: riff.prefix(4), as: UTF8.self) == "RIFF",
            String(decoding: riff.suffix(4), as: UTF8.self) == "WAVE"
        else { throw invalid("Expected a RIFF/WAVE file.") }
        let limit = UInt64(integer(riff, at: 4, bytes: 4)) + 8
        guard limit <= fileSize, limit >= 12 else { throw invalid("The WAV is truncated.") }
        var position: UInt64 = 12
        var format: Data?
        var audio: (offset: UInt64, size: UInt64)?
        while position + 8 <= limit {
            try input.seek(toOffset: position)
            let chunk = try read(input, count: 8)
            let size = UInt64(integer(chunk, at: 4, bytes: 4))
            let start = position + 8
            guard size <= limit - start else { throw invalid("A WAV chunk extends beyond the file.") }
            switch String(decoding: chunk.prefix(4), as: UTF8.self) {
            case "fmt ":
                guard format == nil, (16...4096).contains(size) else {
                    throw invalid("Invalid WAV format chunk.")
                }
                format = try read(input, count: Int(size))
            case "data":
                guard audio == nil else { throw invalid("Multiple WAV audio chunks are unsupported.") }
                audio = (start, size)
            default: break
            }
            position = start + size + size % 2
        }
        guard let format, let audio, audio.size > 0, audio.size % 4 == 0,
            audio.size <= UInt64(UInt32.max) - 36
        else { throw invalid("Missing, oversized or incomplete PCM audio.") }
        try validate(format)
        var header = Data("RIFF".utf8)
        append(UInt32(audio.size + 36), bytes: 4, to: &header)
        header.append(Data("WAVEfmt ".utf8))
        append(16, bytes: 4, to: &header)
        append(1, bytes: 2, to: &header)
        append(2, bytes: 2, to: &header)
        append(44100, bytes: 4, to: &header)
        append(176400, bytes: 4, to: &header)
        append(4, bytes: 2, to: &header)
        append(16, bytes: 2, to: &header)
        header.append(Data("data".utf8))
        append(UInt32(audio.size), bytes: 4, to: &header)
        let temporary = url.deletingLastPathComponent().appendingPathComponent("\(UUID()).wav")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
            throw invalid("Cannot create the prepared PCM file.")
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        do {
            try output.write(contentsOf: header)
            try input.seek(toOffset: audio.offset)
            var remaining = audio.size
            while remaining > 0 {
                try Task.checkCancellation()
                let bytes = try read(input, count: Int(min(remaining, 1_048_576)))
                try output.write(contentsOf: bytes)
                remaining -= UInt64(bytes.count)
                await Task.yield()
            }
            try output.close()
            try input.close()
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? output.close()
            throw error
        }
    }

    private static func validate(_ format: Data) throws {
        let tag = integer(format, at: 0, bytes: 2)
        guard integer(format, at: 2, bytes: 2) == 2,
            integer(format, at: 4, bytes: 4) == 44100,
            integer(format, at: 8, bytes: 4) == 176400,
            integer(format, at: 12, bytes: 2) == 4,
            integer(format, at: 14, bytes: 2) == 16
        else { throw invalid("NetMD requires 44.1 kHz, 16-bit stereo PCM.") }
        if tag == 1 { return }
        let pcmGUID: [UInt8] = [1, 0, 0, 0, 0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113]
        guard tag == 0xfffe, format.count >= 40,
            integer(format, at: 16, bytes: 2) >= 22,
            integer(format, at: 18, bytes: 2) == 16,
            Array(format[24..<40]) == pcmGUID
        else { throw invalid("The WAV does not contain integer PCM samples.") }
    }

    private static func integer(_ data: Data, at offset: Int, bytes: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<bytes { value |= UInt32(data[offset + index]) << (8 * index) }
        return value
    }

    private static func append(_ value: UInt32, bytes: Int, to data: inout Data) {
        for index in 0..<bytes { data.append(UInt8(truncatingIfNeeded: value >> (8 * index))) }
    }

    private static func read(_ file: FileHandle, count: Int) throws -> Data {
        guard let bytes = try file.read(upToCount: count), bytes.count == count else {
            throw invalid("The WAV ended unexpectedly.")
        }
        return bytes
    }

    private static func invalid(_ reason: String) -> BootleggerError {
        return .message("Cannot prepare NetMD audio. \(reason)")
    }
}
