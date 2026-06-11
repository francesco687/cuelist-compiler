import SwiftUI
import SaettaKit

struct CueListView: View {
    @Environment(ProjectStore.self) private var store

    private var activeIndex: Int? {
        store.project.songs.firstIndex(where: { $0.id == store.project.activeSongId })
    }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            if let i = activeIndex {
                if store.project.songs[i].cues.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                            .font(.largeTitle).foregroundStyle(Theme.textFaint)
                        Text("No cues yet")
                            .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textDim)
                        Text("Tap “Add Cue” to start.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    LazyVStack(spacing: 11) {
                        ForEach($store.project.songs[i].cues) { $cue in
                            CueCardView(cue: $cue)
                        }
                    }
                    .padding(.horizontal, 14).padding(.top, 6)
                }

                Button { store.addCue() } label: {
                    Label("Add Cue", systemImage: "plus")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accentSolid)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14).padding(.bottom, 8)
            }
        }
        .scrollContentBackground(.hidden)
    }
}
