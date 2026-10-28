import Foundation
import OSLog

/// Best-effort cleanup reports failures without hiding the original operation's error.
enum FileCleanup {
    private static let logger = Logger(subsystem: "nl.theredhead.Bootlegger", category: "TemporaryFiles")

    static func remove(_ url: URL) {
        do { try FileManager.default.removeItem(at: url) } catch {
            logger.error("Temporary file cleanup failed: \(error.localizedDescription)")
        }
    }
}
