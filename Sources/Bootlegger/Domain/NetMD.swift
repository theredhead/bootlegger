import Foundation

enum NetMDMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case sp
    case lp2
    case lp4

    var id: String { return rawValue }
    var title: String { return rawValue.uppercased() }
    var capacityFactor: Double {
        switch self {
        case .sp: return 1
        case .lp2: return 2
        case .lp4: return 4
        }
    }
}

enum NetMDEncoding: String, CaseIterable, Identifiable, Codable, Sendable {
    case recorder
    case software

    var id: String { return rawValue }
    var title: String { return self == .recorder ? "Recorder" : "Software (ATRAC)" }
}

struct NetMDSettings: Equatable, Sendable {
    static let modeKey = "netmd.mode"
    static let gaplessKey = "netmd.gaplessSP"
    static let encodingKey = "netmd.encoding"
    var mode: NetMDMode = .sp
    var gaplessSP = true
    var encoding: NetMDEncoding = .recorder

    init() {}
    init(defaults: UserDefaults) {
        mode = NetMDMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .sp
        gaplessSP = defaults.object(forKey: Self.gaplessKey) as? Bool ?? true
        encoding = NetMDEncoding(rawValue: defaults.string(forKey: Self.encodingKey) ?? "") ?? .recorder
    }

    func save(to defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: Self.modeKey)
        defaults.set(gaplessSP, forKey: Self.gaplessKey)
        defaults.set(encoding.rawValue, forKey: Self.encodingKey)
    }
}

struct NetMDDevice: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
}

struct NetMDDisc: Codable, Equatable, Sendable {
    struct Track: Codable, Equatable, Sendable {
        var title: String
        var duration: Double
    }
    var device: String
    var title: String
    var trackCount: Int
    var tracks: [Track]
    var writable: Bool
    /// Capacity in SP-equivalent seconds, as reported by the standard NetMD query.
    var availableSeconds: Double
    var totalSeconds: Double
    var supportsLPEncoding: Bool
    var supportsGaplessSP: Bool
    var supportsSoftwareSP = false
    var supportsSoftwareLP = true
    var fingerprint: String
}

enum NetMDPreflight {
    static func usesGapless(disc: NetMDDisc, settings: NetMDSettings) -> Bool {
        return settings.encoding == .recorder && settings.mode == .sp && settings.gaplessSP
            && disc.supportsGaplessSP && disc.trackCount == 0
    }

    static let allocationSeconds = 176.0 * 512 / 44100

    static func requiredSeconds(songs: [Song], mode: NetMDMode, gapless: Bool = false) -> Double {
        let lengths = songs.map { max(0, $0.end - $0.start) / mode.capacityFactor }
        if gapless { return (ceil(lengths.reduce(0, +) / allocationSeconds) + 1) * allocationSeconds }
        return lengths.reduce(0) { $0 + (ceil($1 / allocationSeconds) + 1) * allocationSeconds }
    }

    static func validate(songs: [Song], disc: NetMDDisc, settings: NetMDSettings) throws {
        guard disc.writable else {
            throw BootleggerError.message("The inserted MD is write-protected or not recordable.")
        }
        guard !songs.isEmpty, songs.allSatisfy({ $0.hasValidRange() }) else {
            throw BootleggerError.message("Select tracks with valid ranges before writing to MD.")
        }
        guard songs.allSatisfy({ $0.end - $0.start >= 0.024 }) else {
            throw BootleggerError.message("MiniDisc tracks must be at least 24 milliseconds long.")
        }
        guard disc.trackCount >= 0, disc.trackCount + songs.count <= 255 else {
            throw BootleggerError.message(
                "A MiniDisc supports at most 255 tracks. Deselect tracks or erase the disc.")
        }
        let supported: Bool
        if settings.encoding == .software {
            supported = settings.mode == .sp ? disc.supportsSoftwareSP : disc.supportsSoftwareLP
        } else {
            supported = settings.mode == .sp || disc.supportsLPEncoding
        }
        guard supported else {
            throw BootleggerError.message(
                "This recorder does not support the selected encoding method. Use recorder encoding for SP or software ATRAC for supported LP modes."
            )
        }
        let required = requiredSeconds(
            songs: songs, mode: settings.mode,
            gapless: usesGapless(disc: disc, settings: settings))
        guard disc.availableSeconds.isFinite, disc.availableSeconds >= 0, required.isFinite,
            required <= disc.availableSeconds
        else {
            throw BootleggerError.message(
                "The selected tracks need \(ExportPlan.durationLabel(required)) of SP-equivalent space; the MD has \(ExportPlan.durationLabel(disc.availableSeconds)) available. Deselect tracks or erase the disc."
            )
        }
    }
}
