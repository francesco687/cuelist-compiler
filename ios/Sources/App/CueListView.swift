import SwiftUI
import CuelistCompilerKit

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
                    Text("No cues yet. Tap \u{201C}+ Add Cue\u{201D} to start.")
                        .foregroundStyle(.secondary).padding(.top, 40)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach($store.project.songs[i].cues) { $cue in
                            CueCardView(cue: $cue)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                Button {
                    store.addCue()
                } label: { Label("Add Cue", systemImage: "plus") }
                    .padding(.vertical, 12)
            }
        }
    }
}
