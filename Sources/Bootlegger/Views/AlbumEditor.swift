import SwiftUI

struct AlbumEditor: View {
    @ObservedObject var model: ProjectModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Album").font(.title2.bold())
            ArtworkDropTarget(model: model).frame(height: model.artwork == nil ? 90 : 150)
            Text(
                "Drop an image or use Artwork → Search Artwork. Double-click the cover to pan, zoom and crop."
            )
            .font(.caption).foregroundStyle(.secondary)
            field("Album title", text: $model.project.album.title)
            field("Album artist", text: $model.project.album.artist)
            HStack {
                field("Year / date", text: $model.project.album.year)
                field("Genre", text: $model.project.album.genre)
            }
            field("Venue", text: $model.project.album.venue)
            Text(
                "The album artist groups the songs together in Music. A song can have its own artist override."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $model.isEditingArtwork, onDismiss: { model.cropEditorOriginal = nil }) {
            if let original = model.cropEditorOriginal {
                ArtworkCropEditor(model: model, original: original)
            }
        }
        .textFieldStyle(.roundedBorder)
        .disabled(model.isBusy)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            CommitTextField(title, text: text)
        }
    }
}
