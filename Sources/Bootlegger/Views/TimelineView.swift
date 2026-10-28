import SwiftUI

/// Only the selected song is shown; each song still owns its independent range.
struct TimelineView: View {
    @ObservedObject var model: ProjectModel
    @ObservedObject var playback: Playback

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(model.selectedSong?.title ?? "Timeline").font(
                    .headline)
                Spacer()
                Text("Click to seek • drag handles to trim")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                if let song = model.selectedSong {
                    lane(width: geometry.size.width, song: model.songBinding(for: song))
                } else {
                    lane(width: geometry.size.width, song: nil)
                }
            }
        }
        .disabled(model.isBusy || playback.duration == 0)
    }

    private func lane(width: Double, song: Binding<Song>?) -> some View {
        let duration = max(playback.duration, 0.001)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5).fill(.quaternary)
            if let song {
                let start = min(max(song.wrappedValue.start / duration, 0), 1) * width
                let end = min(max(song.wrappedValue.end / duration, 0), 1) * width
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        model.selectedSongID == song.wrappedValue.id
                            ? Color.accentColor.opacity(0.6) : Color.accentColor.opacity(0.25)
                    )
                    .frame(width: max(0, end - start), height: 28).offset(x: start)
                Text(song.wrappedValue.title).font(.caption).lineLimit(1)
                    .frame(width: max(0, end - start - 20), alignment: .leading).clipped().offset(
                        x: start + 10
                    )
                    .allowsHitTesting(false)
                handle(
                    width: width, value: song.start, other: song.wrappedValue.end, isStart: true,
                    id: song.wrappedValue.id)
                handle(
                    width: width, value: song.end, other: song.wrappedValue.start, isStart: false,
                    id: song.wrappedValue.id)
            }
            Rectangle().fill(.primary).frame(width: 1, height: 34)
                .offset(x: min(playback.position / duration, 1) * width).allowsHitTesting(false)
        }
        .frame(height: 34)
        .coordinateSpace(name: "timeline")
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { location in
            playback.seek(location.x / max(width, 1) * duration)
            model.addSong()
        }
        .onTapGesture { location in
            if let song { model.selectSong(song.wrappedValue.id) }
            playback.seek(location.x / max(width, 1) * duration)
        }
    }

    private func handle(width: Double, value: Binding<Double>, other: Double, isStart: Bool, id: UUID)
        -> some View
    {
        let duration = max(playback.duration, 0.001)
        return RoundedRectangle(cornerRadius: 3).fill(Color.accentColor)
            .frame(width: 9, height: 32)
            .overlay { Capsule().fill(.white.opacity(0.8)).frame(width: 2, height: 14) }
            .offset(x: min(max(value.wrappedValue / duration, 0), 1) * max(width - 9, 0))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
                    .onChanged { drag in
                        guard model.song(id: id) != nil else { return }
                        model.selectSong(id)
                        let time = max(0, min(drag.location.x / max(width, 1) * duration, duration))
                        value.wrappedValue =
                            isStart
                            ? min(time, max(0, other - 0.001)) : max(time, min(duration, other + 0.001))
                        playback.seek(value.wrappedValue)
                    }
            )
            .help(isStart ? "Drag song start" : "Drag song end")
            .accessibilityLabel(isStart ? "Song start boundary" : "Song end boundary")
    }
}
