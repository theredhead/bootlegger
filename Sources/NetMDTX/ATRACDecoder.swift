import Foundation

/// Converts extracted ATRAC1 to PCM using the already bundled offline codec.
enum ATRACDecoder {
    static func decodeSP(_ input: URL) async throws -> URL {
        let executable = ATRACEncoder.executableURL
        return try await Task.detached {
            let output = input.deletingPathExtension().appendingPathExtension("decoded-\(UUID()).wav")
            let process = Process()
            let diagnostics = Pipe()
            process.executableURL = executable
            process.arguments = ["-d", "-i", input.path, "-o", output.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = diagnostics
            try process.run()
            let detail = diagnostics.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: output.path) else {
                try? FileManager.default.removeItem(at: output)
                throw BootleggerError.message(
                    "Cannot decode recorded ATRAC audio. \(String(decoding: detail.prefix(2000), as: UTF8.self))"
                )
            }
            return output
        }.value
    }
}
