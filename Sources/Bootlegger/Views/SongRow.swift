import SwiftUI

struct SongRow: View {
    @ObservedObject var model: ProjectModel
    @ObservedObject var playback: Playback
    let songID: UUID
    @Binding var song: Song

    var body: some View {
        HStack(spacing: 8) {
            Button {
                guard let current = model.song(id: songID) else { return }
                model.selectSong(songID)
                playback.preview(current)
            } label: {
                Image(systemName: model.selectedSongID == songID ? "play.circle.fill" : "play.circle")
            }.help("Preview song from start to end")
            Button {
                model.selectSong(songID)
            } label: {
                Text("\((model.project.songs.firstIndex { $0.id == songID } ?? 0) + 1)").frame(width: 24)
            }.help("Select song without seeking")
            Menu {
                Button("Move Earlier") { model.moveSong(songID, offset: -1) }
                    .disabled(model.project.songs.first?.id == songID)
                Button("Move Later") { model.moveSong(songID, offset: 1) }
                    .disabled(model.project.songs.last?.id == songID)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton).frame(width: 20).help("Change track order and numbering")
            if model.selectedSongID == songID {
                CommitTextField("Song title", text: $song.title).frame(minWidth: 140)
                CommitTextField("Artist (album default)", text: $song.artist).frame(width: 180)
                TimeField(title: "Start", value: $song.start)
                Button {
                    guard model.song(id: songID) != nil else { return }
                    model.selectSong(songID)
                    model.setSongStart()
                } label: {
                    Image(systemName: "arrow.down.to.line")
                }.help("Set start to playhead (S)")
                TimeField(title: "End", value: $song.end)
                Button {
                    guard model.song(id: songID) != nil else { return }
                    model.selectSong(songID)
                    model.setSongEnd()
                } label: {
                    Image(systemName: "arrow.up.to.line")
                }.help("Set end to playhead (E); create the next song when needed")
                Button {
                    if let current = model.song(id: songID) { playback.seek(current.end) }
                } label: {
                    Image(systemName: "forward.end")
                }.help("Preview end boundary")
            } else {
                HStack {
                    Text(song.title).frame(maxWidth: .infinity, alignment: .leading)
                    Text(song.artist).foregroundStyle(.secondary).frame(width: 180, alignment: .leading)
                    Text("\(Timestamp.string(song.start)) – \(Timestamp.string(song.end))")
                        .font(.system(.body, design: .monospaced))
                }
            }
            Button {
                (NSApplication.shared.keyWindow as? ProjectWindow)?.focusPlayback()
                model.removeSong(id: songID)
            } label: {
                Image(systemName: "trash")
            }.help("Remove song")
        }
        .textFieldStyle(.roundedBorder).padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SongRowSelectionRegion(songID: songID))
        .background(
            model.selectedSongID == songID ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6))
    }
}
