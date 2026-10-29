import Foundation

@MainActor
enum NetMDTests {
    static func run() async throws {
        var disc = NetMDDisc(
            device: "Test Recorder", title: "Concert", trackCount: 0, tracks: [],
            writable: true, availableSeconds: 80 * 60, totalSeconds: 80 * 60,
            supportsLPEncoding: false, supportsGaplessSP: true, fingerprint: "original")
        var settings = NetMDSettings()
        let songs = [
            Song(title: "First", start: 0, end: 1200), Song(title: "Second", start: 1300, end: 2500),
        ]
        try NetMDPreflight.validate(songs: songs, disc: disc, settings: settings)
        try SmokeTests.require(
            NetMDPreflight.usesGapless(disc: disc, settings: settings), "gapless SP capability")
        disc.trackCount = 1
        try SmokeTests.require(
            !NetMDPreflight.usesGapless(disc: disc, settings: settings),
            "gapless never rewrites existing tracks")
        disc.availableSeconds = 2300
        try rejected(songs, disc: disc, settings: settings, containing: "space")
        disc.availableSeconds = 4800
        disc.writable = false
        try rejected(songs, disc: disc, settings: settings, containing: "protected")
        disc.writable = true
        settings.mode = .lp2
        try rejected(songs, disc: disc, settings: settings, containing: "SP")
        settings.encoding = .software
        try NetMDPreflight.validate(songs: songs, disc: disc, settings: settings)
        settings.mode = .sp
        try rejected(songs, disc: disc, settings: settings, containing: "encoding")
        settings.mode = .lp2
        settings.encoding = .recorder
        disc.supportsLPEncoding = true
        try NetMDPreflight.validate(songs: songs, disc: disc, settings: settings)
        disc.trackCount = 254
        try rejected(songs, disc: disc, settings: settings, containing: "255")
        disc.trackCount = 0
        disc.availableSeconds = .nan
        try rejected(songs, disc: disc, settings: settings, containing: "space")
        let short = [Song(title: "A", start: 0, end: 1), Song(title: "B", start: 0, end: 1)]
        let separate = NetMDPreflight.requiredSeconds(songs: short, mode: .sp)
        let continuous = NetMDPreflight.requiredSeconds(songs: short, mode: .sp, gapless: true)
        try SmokeTests.require(
            abs(separate - 4 * NetMDPreflight.allocationSeconds) < 0.001
                && abs(continuous - 2 * NetMDPreflight.allocationSeconds) < 0.001,
            "capacity includes allocation rounding and gapless shares allocation")
        settings.mode = .sp
        settings.gaplessSP = false
        disc.availableSeconds = separate
        try NetMDPreflight.validate(songs: short, disc: disc, settings: settings)
        disc.availableSeconds = separate - 0.001
        try rejected(short, disc: disc, settings: settings, containing: "space")
        let suite = "BootleggerMD-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try SmokeTests.require(NetMDSettings(defaults: defaults).gaplessSP, "gapless preference defaults on")
        defaults.set("lp4", forKey: NetMDSettings.modeKey)
        defaults.set(false, forKey: NetMDSettings.gaplessKey)
        let loaded = NetMDSettings(defaults: defaults)
        try SmokeTests.require(
            loaded.mode == .lp4 && !loaded.gaplessSP, "MD settings remain independent of file settings")
        try await transport()
        print(
            "PASS: NetMD capacity/cluster boundaries, write protection, mode capabilities, 255-track limit, settings and helper protocol."
        )
    }

    private static func rejected(
        _ songs: [Song], disc: NetMDDisc, settings: NetMDSettings, containing text: String
    ) throws {
        do {
            try NetMDPreflight.validate(songs: songs, disc: disc, settings: settings)
        } catch {
            try SmokeTests.require(
                error.localizedDescription.localizedCaseInsensitiveContains(text), "MD rejection: \(text)")
            return
        }
        throw BootleggerError.message("Test failed: NetMD preflight accepted \(text)")
    }

    private static func transport() async throws {
        let original = ProcessInfo.processInfo.environment["BOOTLEGGER_NETMD_HELPER"]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NetMDProtocol-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
            if let original {
                setenv("BOOTLEGGER_NETMD_HELPER", original, 1)
            } else {
                unsetenv("BOOTLEGGER_NETMD_HELPER")
            }
        }
        let helper = folder.appendingPathComponent("helper")
        let script = """
            #!/bin/sh
            printf '%s\\n' '{"type":"progress","progress":0.5,"message":"Writing track"}'
            printf '%s\\n' '{"type":"complete","message":"Done"}'
            """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        setenv("BOOTLEGGER_NETMD_HELPER", helper.path, 1)
        var updates: [String] = []
        let events = try await NetMDTransport.run(NetMDRequest(command: "inspect")) { event in
            updates.append(event.type)
        }
        try SmokeTests.require(
            events.count == 2 && updates == ["progress", "complete"], "helper progress delivered in order")
        try
            "#!/bin/sh\nprintf '%s\\n' 'CRITICAL: fixture transfer failure' >&2\nprintf '%s\\n' '{\"type\":\"error\",\"message\":\"Disc changed\"}'\nexit 1\n"
            .write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        do {
            _ = try await NetMDTransport.run(NetMDRequest(command: "inspect")) { _ in }
            throw BootleggerError.message("Test failed: helper error ignored")
        } catch {
            try SmokeTests.require(
                error.localizedDescription.hasPrefix("Disc changed")
                    && error.localizedDescription.contains("CRITICAL: fixture transfer failure")
                    && error.localizedDescription.contains("Diagnostic log:"),
                "helper error and backend details propagate")
        }
        var renamed = NetMDDisc(
            device: "Fixture", title: "Renamed Album", trackCount: 1,
            tracks: [.init(title: "Renamed Track", duration: 60, mode: "sp")], writable: true,
            availableSeconds: 4000, totalSeconds: 4800, supportsLPEncoding: false,
            supportsGaplessSP: false, fingerprint: "after")
        let captured = folder.appendingPathComponent("request.json")
        let json = String(decoding: try JSONEncoder().encode(renamed), as: UTF8.self)
        let response =
            "#!/bin/sh\ncp \"$1\" \"\(captured.path)\"\nprintf '%s\\n' '{\"type\":\"disc\",\"disc\":\(json)}'\n"
        try response.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        var snapshot = renamed
        snapshot.fingerprint = "before"
        try await NetMDController.shared.rename(title: "Renamed Track", track: 0, confirmedDisc: snapshot)
        var request = try JSONSerialization.jsonObject(with: Data(contentsOf: captured)) as! [String: Any]
        try SmokeTests.require(
            request["command"] as? String == "rename" && request["trackIndex"] as? Int == 0
                && request["fingerprint"] as? String == "before"
                && NetMDController.shared.disc?.fingerprint == "after" && !NetMDController.shared.isBusy,
            "track rename sends the captured disc identity and applies readback")
        try await NetMDController.shared.rename(title: "Renamed Album", track: nil, confirmedDisc: snapshot)
        request = try JSONSerialization.jsonObject(with: Data(contentsOf: captured)) as! [String: Any]
        try SmokeTests.require(
            request["trackIndex"] == nil && request["title"] as? String == "Renamed Album",
            "album rename omits the track index")
        let library = TXLibrary()
        for invalid in [String(repeating: "x", count: 121), "line\nbreak", "reserved//group"] {
            library.error = nil
            library.rename(title: invalid, track: nil, disc: snapshot)
            try SmokeTests.require(
                library.error != nil && !library.isRenaming,
                "invalid titles are rejected before any metadata write")
        }
        var ordered = snapshot
        ordered.trackCount = 2
        ordered.tracks.append(.init(title: "Second", duration: 30, mode: "sp"))
        var moved = ordered
        moved.tracks.reverse()
        moved.fingerprint = "reordered"
        let orderJSON = String(decoding: try JSONEncoder().encode(moved), as: UTF8.self)
        let orderResponse =
            "#!/bin/sh\ncp \"$1\" \"\(captured.path)\"\nprintf '%s\\n' '{\"type\":\"disc\",\"disc\":\(orderJSON)}'\n"
        try orderResponse.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        try await NetMDController.shared.reorder(order: [1, 0], confirmedDisc: ordered)
        request = try JSONSerialization.jsonObject(with: Data(contentsOf: captured)) as! [String: Any]
        try SmokeTests.require(
            request["command"] as? String == "reorder"
                && request["trackOrder"] as? [Int] == [1, 0]
                && request["fingerprint"] as? String == ordered.fingerprint
                && NetMDController.shared.disc?.tracks == moved.tracks,
            "reorder sends a complete permutation and applies actual device readback")
        ordered.writable = false
        try SmokeTests.require(
            !library.reorder(order: [1, 0], disc: ordered), "protected discs reject reorder drops")
        renamed.writable = false
        do {
            try await NetMDController.shared.rename(title: "Forbidden", track: 0, confirmedDisc: renamed)
            throw BootleggerError.message("Test failed: renamed a protected disc")
        } catch {
            try SmokeTests.require(
                error.localizedDescription.contains("protected"), "rename refuses write-protected discs")
        }
        if let original {
            setenv("BOOTLEGGER_NETMD_HELPER", original, 1)
            if ProcessInfo.processInfo.environment["BOOTLEGGER_SKIP_USB_PROBE"] != "1" {
                // Read-only discovery must return a disc or a structured error, never crash.
                do {
                    let discovered = try await NetMDTransport.run(NetMDRequest(command: "inspect")) { _ in }
                    try SmokeTests.require(discovered.last?.disc != nil, "native read-only discovery result")
                } catch {
                    try SmokeTests.require(
                        !error.localizedDescription.contains("stopped unexpectedly"),
                        "native discovery returns a structured error when unavailable")
                }
            }
            do {
                _ = try await NetMDTransport.run(NetMDRequest(command: "invalid")) { _ in }
                throw BootleggerError.message("Test failed: native helper accepted unknown command")
            } catch {
                try SmokeTests.require(
                    error.localizedDescription.contains("Unknown NetMD command"),
                    "native helper validates before accessing USB")
            }
        }
    }
}
