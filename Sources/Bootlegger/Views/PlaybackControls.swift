import SwiftUI

struct PlaybackControls: View {
    @ObservedObject var model: ProjectModel
    @ObservedObject var playback: Playback

    var body: some View {
        HStack {
            Button {
                playback.seek(playback.position - 5)
            } label: {
                Image(systemName: "gobackward.5")
            }
            .help("Back five seconds")
            Button(action: playback.toggle) {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
            }
            .help("Play or pause")
            Button {
                playback.seek(playback.position + 5)
            } label: {
                Image(systemName: "goforward.5")
            }
            .help("Forward five seconds")
            Slider(
                value: Binding(get: { playback.position }, set: { playback.seek($0) }),
                in: 0...max(playback.duration, 0.001)
            )
            .accessibilityLabel("Recording position")
            Text("\(Timestamp.string(playback.position)) / \(Timestamp.string(playback.duration))")
                .font(.system(.caption, design: .monospaced))
        }
        .disabled(model.sourceURL == nil || model.isBusy)
    }
}
