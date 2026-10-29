import AVFoundation
import AppKit

@MainActor
enum TXExtractionTests {
    static func run(directory: URL) async throws {
        try SmokeTests.require(
            TXTrackOrder.moving(IndexSet([1, 3]), to: 5, count: 5) == [0, 2, 4, 1, 3],
            "discontiguous tracks move down together in their original order")
        try SmokeTests.require(
            TXTrackOrder.moving(IndexSet([2, 3]), to: 0, count: 5) == [2, 3, 0, 1, 4],
            "multiple tracks move up to the insertion point")
        try SmokeTests.require(
            TXTrackOrder.moving(IndexSet([1, 2]), to: 3, count: 4) == [0, 1, 2, 3],
            "dropping immediately after the selection is a no-op")
        try SmokeTests.require(
            TXTrackOrder.moving(IndexSet([9]), to: 0, count: 3) == nil
                && TXTrackOrder.moving(IndexSet([1]), to: 5, count: 3) == nil,
            "invalid rows and insertion points are rejected")
        let raw = directory.appendingPathComponent("NetMD-prepared.aea")
        try await verifyDecoderBoundaries(raw: raw, directory: directory)
        var disc = NetMDDisc(
            device: "Sony MZ-RH1", title: "Test", trackCount: 1,
            tracks: [.init(title: "A/B: Concert", duration: 1, mode: "sp")], writable: false,
            availableSeconds: 0, totalSeconds: 4800, supportsLPEncoding: false,
            supportsGaplessSP: false, fingerprint: "test", supportsNativeSPRead: true)
        try SmokeTests.require(
            TXPromisedTrack.supports(disc, index: 0), "write protection does not block reading")
        try SmokeTests.require(
            !TXPromisedTrack.supports(disc, index: 1), "stale track indices cannot be dragged")
        disc.tracks[0].mode = "lp2"
        try SmokeTests.require(
            !TXPromisedTrack.supports(disc, index: 0), "unsupported recording formats cannot be promised")
        disc.tracks[0].mode = "sp"
        var active = 0
        var maximum = 0
        var reads = 0
        let extraction = TXExtraction { _, _, destination in
            active += 1
            maximum = max(maximum, active)
            defer { active -= 1 }
            try await Task.sleep(for: .milliseconds(20))
            try FileManager.default.copyItem(at: raw, to: destination)
            reads += 1
        }
        let original = TXPromisedTrack(disc: disc, index: 0, convertToWAV: false)
        let converted = TXPromisedTrack(disc: disc, index: 0, convertToWAV: true)
        try SmokeTests.require(
            original.filename == "1-A-B- Concert.aea", "Finder filenames sanitize track titles")
        let drag = extraction.provider(for: original, row: 0)
        try SmokeTests.require(
            drag.writableTypes(for: .general).contains(TXTrackFilePromise.rowType)
                && drag.pasteboardPropertyList(forType: TXTrackFilePromise.rowType) as? String == "0"
                && drag.writingOptions(forType: TXTrackFilePromise.rowType, pasteboard: .general).isEmpty,
            "local reorder identity coexists with Finder promises without starting extraction")
        _ = extraction.provider(for: converted)
        try SmokeTests.require(reads == 0, "starting a drag does not read the device")
        let aea = directory.appendingPathComponent(original.filename)
        let wav = directory.appendingPathComponent(converted.filename)
        async let one: Void = fulfill(original, extraction: extraction, destination: aea)
        async let two: Void = fulfill(converted, extraction: extraction, destination: wav)
        try await one
        try await two
        let data = try Data(contentsOf: aea)
        let expected = try Data(contentsOf: raw)
        let duration = try await AVURLAsset(url: wav).load(.duration).seconds
        try SmokeTests.require(
            data == expected && abs(duration - 1) < 0.1, "Finder receives original ATRAC or decoded WAV")
        try SmokeTests.require(
            maximum == 1 && reads == 2 && extraction.pendingCount == 0,
            "multiple file promises serialize device ownership")
        do {
            try await extraction.extract(original, to: aea)
            throw BootleggerError.message("Test failed: extraction overwrote an existing file")
        } catch {
            try SmokeTests.require(reads == 2, "existing files are rejected before opening the recorder")
        }
        let batchID = UUID()
        extraction.prepareBatch(id: batchID, count: 2)
        let batched = TXPromisedTrack(disc: disc, index: 0, convertToWAV: false, batchID: batchID)
        try await fulfill(
            batched, extraction: extraction,
            destination: directory.appendingPathComponent("batch-first.aea"))
        try SmokeTests.require(
            extraction.isActive && extraction.totalCount == 2 && extraction.completedCount == 1
                && extraction.currentNumber == 2 && extraction.overallProgress(trackProgress: 1) == 0.5,
            "overall progress and modal lifetime include Finder promises requested later")
        try await fulfill(
            batched, extraction: extraction,
            destination: directory.appendingPathComponent("batch-second.aea"))
        try SmokeTests.require(
            !extraction.isActive && extraction.completedCount == 2
                && extraction.overallProgress(trackProgress: 1) == 1,
            "the modal closes only after the complete selection finishes")
        print(
            "PASS: Finder file promises defer and serialize reads, preserve ATRAC, decode WAV, gate capabilities and refuse replacement."
        )
    }

    private static func verifyDecoderBoundaries(raw: URL, directory: URL) async throws {
        let original = try Data(contentsOf: raw)
        let channels = Int(original[264])
        let bytesPerGroup = 212 * channels
        let groups = (original.count - 2048) / bytesPerGroup
        for remainder in 0..<8 {
            let count = groups - (groups - remainder) % 8
            var fixture = Data(original.prefix(2048 + count * bytesPerGroup))
            let units = count * channels
            for byte in 0..<4 { fixture[260 + byte] = UInt8((units >> (8 * byte)) & 255) }
            let path = directory.appendingPathComponent("decoder-boundary-\(remainder).aea")
            try fixture.write(to: path)
            let decoded = try await ATRACDecoder.decodeSP(path)
            let duration = try await AVURLAsset(url: decoded).load(.duration).seconds
            let expected = Double(count - 5) * 512 / 44100
            try SmokeTests.require(
                abs(duration - expected) < 0.001,
                "ATRAC decoder stops at the exact frame boundary for remainder \(remainder)")
        }
    }

    private static func fulfill(
        _ track: TXPromisedTrack, extraction: TXExtraction, destination: URL
    ) async throws {
        let provider = extraction.provider(for: track)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            extraction.filePromiseProvider(provider, writePromiseTo: destination) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
