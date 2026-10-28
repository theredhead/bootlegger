import SwiftUI

struct FileExportOptions: View {
    @Binding var settings: FileExportSettings
    var exampleProject: Project?

    private var example: String {
        var project = exampleProject ?? Project()
        if project.album.title.isEmpty { project.album.title = "Concert" }
        if project.album.artist.isEmpty { project.album.artist = "Artist" }
        if project.album.year.isEmpty { project.album.year = "2026" }
        let song = project.songs.first ?? Song(title: "Opening Song", start: 0, end: 60)
        return FilenameToken.render(settings.filenameTemplate, project: project, song: song, index: 0)
            + "." + settings.format.filenameExtension
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Format", selection: $settings.format) {
                    ForEach(AudioFileFormat.allCases) { format in Text(format.title).tag(format) }
                }
                if settings.format == .aac {
                    Picker("Bitrate", selection: $settings.bitrate) {
                        ForEach([128, 192, 256, 320], id: \.self) { rate in Text("\(rate) kbps").tag(rate) }
                    }
                } else {
                    Picker("Bit depth", selection: $settings.bitDepth) {
                        Text("16 bit").tag(16)
                        Text("24 bit").tag(24)
                    }
                }
            }
            Picker("Sample rate", selection: $settings.sampleRate) {
                Text("44.1 kHz").tag(44100)
                Text("48 kHz").tag(48000)
            }
            Text(
                settings.format.supportsAlbumMetadata
                    ? "Album tags and artwork are embedded. Audio is exported in stereo."
                    : "Uncompressed stereo audio. Album tags and artwork are not embedded in this format."
            )
            .font(.caption).foregroundStyle(.secondary)
            Text("Filename format").font(.headline)
            FilenameFormatField(template: $settings.filenameTemplate).frame(height: 28)
            HStack(spacing: 6) {
                ForEach(FilenameToken.allCases, id: \.rawValue) { token in
                    Text(token.title)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                        .onDrag { NSItemProvider(object: token.rawValue as NSString) }
                        .onTapGesture { settings.filenameTemplate += token.rawValue }
                        .help("Drag into the format field, or click to append")
                }
            }
            HStack {
                Text("Preview: \(example)").font(.caption).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Reset Format") { settings.filenameTemplate = FileExportSettings.defaultTemplate }
                    .controlSize(.small)
            }
        }
    }
}

struct ExportSettingsView: View {
    @AppStorage(ExportStrategy.preferenceKey) private var strategy = ExportStrategy.files.rawValue
    @State private var settings = FileExportSettings(defaults: .standard)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Default export strategy", selection: $strategy) {
                ForEach(ExportStrategy.allCases) { option in Text(option.title).tag(option.rawValue) }
            }
            TabView {
                FileExportOptions(settings: $settings)
                    .padding().tabItem { Text("Files") }
                Text(
                    "NetMD writing is not implemented yet. Device and compression settings will appear here when supported."
                )
                .padding().tabItem { Text("MD") }
                Text(
                    "CD writing is not implemented yet. Burner and disc settings will appear here when supported."
                )
                .padding().tabItem { Text("CD") }
            }
        }
        .padding(24)
        .frame(width: 640, height: 360)
        .onChange(of: settings) { _, value in
            let defaults = UserDefaults.standard
            defaults.set(value.format.rawValue, forKey: FileExportSettings.formatKey)
            defaults.set(value.bitrate, forKey: FileExportSettings.bitrateKey)
            defaults.set(value.bitDepth, forKey: FileExportSettings.bitDepthKey)
            defaults.set(value.sampleRate, forKey: FileExportSettings.sampleRateKey)
            defaults.set(value.filenameTemplate, forKey: FileExportSettings.filenameKey)
        }
    }
}
