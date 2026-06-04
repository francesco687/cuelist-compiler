import SwiftUI
import CuelistCompilerKit

struct SongBarView: View {
    @Environment(ProjectStore.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 10) {
            Menu {
                ForEach(store.project.songs) { song in
                    Button {
                        store.setActiveSong(song.id)
                    } label: {
                        Label(song.name.isEmpty ? "(untitled)" : song.name,
                              systemImage: song.id == store.project.activeSongId ? "checkmark" : "")
                    }
                }
                Divider()
                Button("New Song") { store.addSong() }
                if store.project.songs.count > 1 {
                    Button("Remove \"\(store.activeSong.name.isEmpty ? "(untitled)" : store.activeSong.name)\"",
                           role: .destructive) {
                        store.removeSong(id: store.project.activeSongId)
                    }
                }
            } label: {
                HStack { Text(store.activeSong.name.isEmpty ? "(untitled)" : store.activeSong.name)
                    Image(systemName: "chevron.down").font(.caption) }
            }

            Spacer()

            // Song name + sequence editors bound to the active song.
            if let idx = store.project.songs.firstIndex(where: { $0.id == store.project.activeSongId }) {
                TextField("Song name", text: $store.project.songs[idx].name)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 160)
                Stepper("Seq \(store.project.songs[idx].sequence)",
                        value: $store.project.songs[idx].sequence, in: 1...9999)
                    .labelsHidden()
                Text("Seq \(store.project.songs[idx].sequence)").font(.caption).monospacedDigit()
            }
        }
        .padding(.horizontal).padding(.vertical, 6)
        .background(.bar)
    }
}
