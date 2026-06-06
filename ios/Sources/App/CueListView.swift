import SwiftUI
import SaettaKit

struct CueListView: View {
    @Environment(ProjectStore.self) private var store
    @Binding var selection: Set<UUID>

    private var activeIndex: Int? {
        store.project.songs.firstIndex(where: { $0.id == store.project.activeSongId })
    }

    var body: some View {
        @Bindable var store = store
        if let i = activeIndex {
            if store.project.songs[i].cues.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.largeTitle).foregroundStyle(Theme.textFaint)
                    Text("No cues yet")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textDim)
                    Text("Tap \u{201C}Add Cue\u{201D} to start.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.top, 60)
            } else {
                List(selection: $selection) {
                    ForEach($store.project.songs[i].cues) { $cue in
                        CueCardView(cue: $cue)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                    }
                    .onMove { store.moveCues(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
            }
        }
    }
}
