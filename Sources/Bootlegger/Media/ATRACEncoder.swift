import Foundation

/// Runs the bundled offline encoder. PCM preparation and USB transfer remain separate steps.
enum ATRACEncoder {
    static var executableURL: URL {
        if let override = ProcessInfo.processInfo.environment["BOOTLEGGER_ATRAC_ENCODER"] {
            return URL(fileURLWithPath: override)
        }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/BootleggerATRAC")
    }

    static func encode(_ input: URL, mode: NetMDMode) async throws -> URL {
        let executable = executableURL
        return try await Task.detached {
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw BootleggerError.message("The bundled ATRAC encoder is missing. Rebuild Bootlegger.")
            }
            let output = input.deletingPathExtension().appendingPathExtension(mode == .sp ? "aea" : "at3")
            let process = Process()
            let diagnostics = Pipe()
            process.executableURL = executable
            var arguments = [
                "-e", mode == .sp ? "atrac1" : mode == .lp4 ? "atrac3_lp4" : "atrac3",
                "-i", input.path, "-o", output.path,
            ]
            if mode != .sp { arguments += ["--bitrate", mode == .lp2 ? "128" : "64"] }
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = diagnostics
            try process.run()
            let detail = diagnostics.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: output.path) else {
                try? FileManager.default.removeItem(at: output)
                let message = String(decoding: detail.prefix(2000), as: UTF8.self)
                throw BootleggerError.message("ATRAC encoding failed. \(message)")
            }
            return output
        }.value
    }
}
