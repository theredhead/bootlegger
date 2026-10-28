import Foundation

enum AudioFileFormat: String, CaseIterable, Identifiable {
    case aac
    case appleLossless
    case wav
    case aiff
    case caf

    var id: String { return rawValue }
    var title: String {
        switch self {
        case .aac: return "AAC (.m4a)"
        case .appleLossless: return "Apple Lossless (.m4a)"
        case .wav: return "WAV (PCM)"
        case .aiff: return "AIFF (PCM)"
        case .caf: return "CAF (PCM)"
        }
    }
    var filenameExtension: String {
        switch self {
        case .aac, .appleLossless: return "m4a"
        case .wav: return "wav"
        case .aiff: return "aiff"
        case .caf: return "caf"
        }
    }
    var supportsAlbumMetadata: Bool { return self == .aac || self == .appleLossless }
}

struct FileExportSettings: Equatable {
    static let formatKey = "fileExport.format"
    static let bitrateKey = "fileExport.bitrate"
    static let bitDepthKey = "fileExport.bitDepth"
    static let sampleRateKey = "fileExport.sampleRate"
    static let filenameKey = "fileExport.filename"
    static let defaultTemplate = "<track #>-<track name>"
    var format: AudioFileFormat = .aac
    var bitrate = 256
    var bitDepth = 16
    var sampleRate = 44100
    var filenameTemplate = defaultTemplate

    init() {}

    init(defaults: UserDefaults) {
        format = AudioFileFormat(rawValue: defaults.string(forKey: Self.formatKey) ?? "") ?? .aac
        let bitrate = defaults.integer(forKey: Self.bitrateKey)
        self.bitrate = [128, 192, 256, 320].contains(bitrate) ? bitrate : 256
        let depth = defaults.integer(forKey: Self.bitDepthKey)
        bitDepth = [16, 24].contains(depth) ? depth : 16
        let rate = defaults.integer(forKey: Self.sampleRateKey)
        sampleRate = [44100, 48000].contains(rate) ? rate : 44100
        filenameTemplate = defaults.string(forKey: Self.filenameKey) ?? Self.defaultTemplate
    }

    func save(to defaults: UserDefaults) {
        defaults.set(format.rawValue, forKey: Self.formatKey)
        defaults.set(bitrate, forKey: Self.bitrateKey)
        defaults.set(bitDepth, forKey: Self.bitDepthKey)
        defaults.set(sampleRate, forKey: Self.sampleRateKey)
        defaults.set(filenameTemplate, forKey: Self.filenameKey)
    }

    func filenames(project: Project) throws -> [String] {
        guard !filenameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BootleggerError.message("Enter a filename format before exporting.")
        }
        let names = project.songs.enumerated().map { index, song in
            return FilenameToken.render(filenameTemplate, project: project, song: song, index: index)
                + "." + format.filenameExtension
        }
        let unique = Set(names.map { $0.precomposedStringWithCanonicalMapping.lowercased() })
        guard unique.count == names.count else {
            throw BootleggerError.message(
                "The filename format produces duplicate names. Add the Track # token.")
        }
        return names
    }
}

enum FilenameToken: String, CaseIterable {
    case trackNumber = "<track #>"
    case trackName = "<track name>"
    case artist = "<artist>"
    case album = "<album>"
    case albumArtist = "<album artist>"
    case year = "<year>"

    var title: String { return String(rawValue.dropFirst().dropLast()).capitalized }

    static func pieces(_ template: String) -> [String] {
        var remaining = template[...]
        var result: [String] = []
        while !remaining.isEmpty {
            let match = allCases.compactMap { token -> Range<Substring.Index>? in
                return remaining.range(of: token.rawValue)
            }.min { $0.lowerBound < $1.lowerBound }
            guard let match else {
                result.append(String(remaining))
                break
            }
            if match.lowerBound > remaining.startIndex {
                result.append(String(remaining[..<match.lowerBound]))
            }
            result.append(String(remaining[match]))
            remaining = remaining[match.upperBound...]
        }
        return result
    }

    static func render(_ template: String, project: Project, song: Song, index: Int) -> String {
        // Replace each parsed token once; metadata containing token-like text remains literal.
        let values: [FilenameToken: String] = [
            .trackNumber: String(format: "%02d", index + 1), .trackName: song.title,
            .artist: song.artist.isEmpty ? project.album.artist : song.artist,
            .album: project.album.title, .albumArtist: project.album.artist, .year: project.album.year,
        ]
        let name = pieces(template).map { part in
            return FilenameToken(rawValue: part).flatMap { values[$0] } ?? part
        }.joined()
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let clean = name.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = clean.isEmpty || clean == "." || clean == ".." ? "Untitled" : clean
        var result = ""
        for character in valid {
            guard result.utf8.count + String(character).utf8.count <= 180 else { break }
            result.append(character)
        }
        return result
    }
}
