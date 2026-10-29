import SwiftUI

struct SongList: View {
    @ObservedObject var model: ProjectModel
    @ObservedObject var playback: Playback

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Songs").font(.headline)
                Text("\(model.project.songs.count)").foregroundStyle(.secondary)
                Spacer()
                Text("Ranges are independent; gaps and overlaps are allowed.").font(.caption).foregroundStyle(
                    .secondary)
            }.padding(.horizontal)
            if model.project.songs.isEmpty {
                ContentUnavailableView(
                    "No songs yet", systemImage: "music.note.list",
                    description: Text("Seek to a song's beginning, then click Add Song.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.project.songs) { song in
                            SongRow(
                                model: model, playback: playback, songID: song.id,
                                song: model.songBinding(for: song))
                        }
                    }.padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 10)
        .disabled(model.isBusy)
    }
}
