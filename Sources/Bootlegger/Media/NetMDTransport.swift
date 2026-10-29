import Foundation

struct NetMDRequest: Encodable, Sendable {
    struct Track: Encodable, Sendable {
        var path: String
        var title: String
        var duration: Double
    }
    var command: String
    var fingerprint: String?
    var title: String?
    var mode: NetMDMode?
    var encoding: NetMDEncoding?
    var gapless: Bool?
    var tracks: [Track]?
    var cancelPath: String?
    var recoveryPath: String?
    var trackIndex: Int?
    var outputPath: String?
    var trackOrder: [Int]?
}

struct NetMDEvent: Decodable, Sendable {
    var type: String
    var disc: NetMDDisc?
    var devices: [NetMDDevice]?
    var progress: Double?
    var message: String?
}

/// Owns the helper process and pipe lifetime; no shell commands or USB handles escape this boundary.
enum NetMDTransport {
    static var helperURL: URL {
        if let override = ProcessInfo.processInfo.environment["BOOTLEGGER_NETMD_HELPER"] {
            return URL(fileURLWithPath: override)
        }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/BootleggerNetMD")
    }

    static func run(
        _ request: NetMDRequest,
        progress: @escaping @MainActor @Sendable (NetMDEvent) -> Void
    ) async throws -> [NetMDEvent] {
        let executable = helperURL
        return try await Task.detached {
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw BootleggerError.message(
                    "The bundled NetMD helper is missing. Rebuild Bootlegger with its NetMD build phase.")
            }
            let requestURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                "NetMD-\(UUID()).json")
            try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: requestURL) }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executable
            process.arguments = [requestURL.path]
            process.standardOutput = pipe
            let logDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "BootleggerNetMDLogs")
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let logURL = logDirectory.appendingPathComponent("\(UUID()).log")
            guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
                throw BootleggerError.message("Cannot create NetMD diagnostic log.")
            }
            let diagnosticFile = try FileHandle(forWritingTo: logURL)
            defer { try? diagnosticFile.close() }
            // Drain stderr directly to a file, so long transfers cannot block on a full pipe.
            process.standardError = diagnosticFile
            try process.run()
            defer { pipe.fileHandleForReading.closeFile() }
            var pending = Data()
            var events: [NetMDEvent] = []
            while true {
                let chunk = pipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                pending.append(chunk)
                guard pending.count <= 1_000_000 else {
                    throw BootleggerError.message("The NetMD helper returned an oversized response.")
                }
                while let newline = pending.firstIndex(of: 10) {
                    let line = pending[..<newline]
                    pending.removeSubrange(...newline)
                    let event = try JSONDecoder().decode(NetMDEvent.self, from: line)
                    events.append(event)
                    await progress(event)
                }
            }
            process.waitUntilExit()
            if let error = events.last(where: { $0.type == "error" }) {
                try? diagnosticFile.synchronize()
                let detail = diagnosticTail(logURL)
                let summary = error.message ?? "NetMD operation failed."
                let context = detail.isEmpty ? summary : "\(summary)\n\n\(detail)"
                let message = "\(context)\n\nDiagnostic log: \(logURL.path)"
                throw BootleggerError.message(message)
            }
            guard process.terminationStatus == 0, pending.isEmpty, !events.isEmpty else {
                throw BootleggerError.message(
                    "The NetMD helper stopped unexpectedly. Reconnect the recorder and refresh the disc.\n\nDiagnostic log: \(logURL.path)"
                )
            }
            try? FileManager.default.removeItem(at: logURL)
            return events
        }.value
    }

    private static func diagnosticTail(_ url: URL) -> String {
        guard let file = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd(),
            (try? file.seek(toOffset: size > 8192 ? size - 8192 : 0)) != nil,
            let data = try? file.readToEnd()
        else { return "" }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
            .filter { $0.contains("CRITICAL") || $0.contains("WARN") }
        return lines.suffix(4).joined(separator: "\n")
    }
}
