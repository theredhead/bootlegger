import AVKit
import SwiftUI

struct ProjectView: View {
    @ObservedObject var model: ProjectModel
    @State private var metadataHeight: CGFloat = 560

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HSplitView {
                    VStack(spacing: 8) {
                        VideoPlayerView(
                            player: model.playback.player,
                            importRecording: { url in Task { model.importRecording(from: url) } }
                        )
                        .frame(minHeight: 220)
                        .overlay {
                            if model.sourceURL == nil {
                                ContentUnavailableView(
                                    "Open a concert", systemImage: "film",
                                    description: Text(
                                        "Drop an audio or video recording here, or choose Import Recording. Bootlegger keeps its own copy in your project."
                                    ))
                            } else if !model.playback.hasVideo {
                                ContentUnavailableView(
                                    "Audio recording", systemImage: "waveform",
                                    description: Text(
                                        "Use the playback controls and audio levels below. Drop an image onto the artwork area to add a cover."
                                    )
                                )
                                .allowsHitTesting(false)
                            }
                        }
                        PlaybackControls(model: model, playback: model.playback)
                        TimelineView(model: model, playback: model.playback)
                            .frame(height: 56)
                        AudioLevelView(model: model, playback: model.playback, levels: model.audioLevels)
                            .frame(height: 82)
                    }
                    .padding()
                    .frame(minWidth: 550)
                    ScrollView {
                        AlbumEditor(model: model)
                            .background(
                                GeometryReader { content in
                                    Color.clear.preference(
                                        key: MetadataHeightPreference.self, value: content.size.height + 32)
                                })
                    }
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
                    .padding()
                }
                .frame(height: max(0, min(metadataHeight, geometry.size.height - 142)))
                Divider()
                SongList(model: model, playback: model.playback)
                    .frame(minHeight: 100, maxHeight: .infinity)
                    .layoutPriority(1)
                Divider()
                HStack {
                    if model.isBusy { ProgressView().controlSize(.small) }
                    Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    if model.isExporting {
                        ProgressView(value: model.exportProgress).frame(width: 100)
                        Button("Cancel", action: model.cancelExport)
                    }
                }
                .padding(10)
            }
        }
        .onPreferenceChange(MetadataHeightPreference.self) { metadataHeight = max(440, $0) }
        .onSubmit { (NSApplication.shared.keyWindow as? ProjectWindow)?.focusPlayback() }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1, let url = urls.first, ProjectModel.isRecording(url) else { return false }
            Task { model.importRecording(from: url) }
            return true
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: model.importRecording) {
                    Label("Import Recording", systemImage: "plus.rectangle.on.rectangle")
                }
                .disabled(model.isBusy)
                Button(action: model.addSong) { Label("Add Song", systemImage: "plus") }
                    .disabled(model.isBusy || model.sourceURL == nil)
                Button(action: model.exportAudio) {
                    Label("Export Album", systemImage: "square.and.arrow.up")
                }
                .disabled(model.isBusy || model.sourceURL == nil || model.project.songs.isEmpty)
            }
        }
        .alert(
            "Bootlegger",
            isPresented: Binding(
                get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct MetadataHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
