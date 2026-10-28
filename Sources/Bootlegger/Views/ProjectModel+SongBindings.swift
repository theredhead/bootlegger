import SwiftUI

extension ProjectModel {
    /// SwiftUI may read or finish editing a removed row during reconciliation.
    /// Resolve identity on every access; stale writes must never modify a shifted row.
    func songBinding(for snapshot: Song) -> Binding<Song> {
        return Binding(
            get: { self.song(id: snapshot.id) ?? snapshot },
            set: { updated in
                guard updated.id == snapshot.id else { return }
                self.updateSong(updated)
            })
    }
}
