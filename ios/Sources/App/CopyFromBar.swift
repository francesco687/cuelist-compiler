import SwiftUI
import CuelistCompilerKit

struct CopyFromBar: View {
    @Environment(ProjectStore.self) private var store
    @Binding var cue: Cue

    /// Other cues in the active song that have at least one non-empty group block.
    private var sources: [Cue] {
        store.activeSong.cues.filter { other in
            other.id != cue.id &&
            other.actions.contains { !$0.group.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    var body: some View {
        if !sources.isEmpty {
            Menu {
                ForEach(sources) { src in
                    Button("Cue \(src.n, format: .number)\(src.name.isEmpty ? "" : " — \(src.name)")") {
                        store.copyActions(fromCueId: src.id, toCueId: cue.id)
                    }
                }
            } label: {
                Label("Copy from cue…", systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accentSolid)
            }
        }
    }
}
