import Foundation

@MainActor
enum TXQueueTests {
    static func run(source: URL, directory: URL) async throws {
        let library = TXLibrary()
        await library.enqueue([source, source])
        try SmokeTests.require(
            library.queue.count == 2 && library.queue.allSatisfy { $0.duration > 0 },
            "TX accepts playable recordings and preserves intentional duplicate copies")
        let first = library.queue[0].id
        library.remove(first)
        try SmokeTests.require(library.queue.count == 1, "TX removes only the selected queued copy")
        let invalid = directory.appendingPathComponent("not-a-recording.txt")
        try Data("not audio".utf8).write(to: invalid)
        await library.enqueue([source, invalid])
        try SmokeTests.require(
            library.queue.count == 1 && library.error != nil,
            "TX rejects an invalid batch atomically without losing the existing queue")
        print(
            "PASS: TX recording queue validation, duplicate copies, removal and atomic invalid-batch rejection."
        )
    }
}
