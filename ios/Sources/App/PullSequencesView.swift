import SwiftUI
import CuelistCompilerKit

/// "Pull from MA" — asks the hub for the sequence list in the loaded showfile
/// and shows it, searchable. Display-only for now (picking a sequence to pull its
/// cues is a later phase).
struct PullSequencesView: View {
    @Environment(HubClient.self) private var hub
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Pull from MA")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { hub.pullSequences() } label: { Image(systemName: "arrow.clockwise") }
                            .disabled(!hub.state.isOnline || hub.isPulling)
                    }
                }
        }
        .task {
            // Pull once on open if we don't already have a list. Refresh button re-pulls.
            if hub.state.isOnline, hub.sequences == nil, !hub.isPulling { hub.pullSequences() }
        }
    }

    @ViewBuilder private var content: some View {
        if !hub.state.isOnline {
            status("Hub offline", "Connect to the hub first, then pull.", "wifi.slash")
        } else if hub.isPulling, hub.sequences == nil {
            ProgressView("Pulling from MA…")
        } else if let err = hub.pullError, hub.sequences == nil {
            status("Pull failed", err, "exclamationmark.triangle")
        } else if let seqs = hub.sequences {
            list(seqs)
        } else {
            ProgressView("Pulling from MA…")
        }
    }

    private func list(_ seqs: [PulledSequence]) -> some View {
        let shown = filter(seqs)
        return List {
            Section {
                ForEach(shown) { seq in
                    HStack(spacing: 12) {
                        Text(number(seq))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 56, alignment: .leading)
                        Text(seq.name.isEmpty ? "—" : seq.name)
                        Spacer()
                    }
                }
            } header: {
                Text(shown.count == seqs.count
                     ? "\(seqs.count) sequences"
                     : "\(shown.count) of \(seqs.count)")
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Search sequences")
        .overlay {
            if shown.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }

    private func filter(_ seqs: [PulledSequence]) -> [PulledSequence] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return seqs }
        return seqs.filter { $0.name.localizedCaseInsensitiveContains(q) || number($0).contains(q) }
    }

    /// Sequence numbers are integers in MA; show them without a trailing ".0".
    private func number(_ s: PulledSequence) -> String {
        s.no == s.no.rounded() ? String(Int(s.no)) : String(s.no)
    }

    private func status(_ title: String, _ message: String, _ symbol: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
    }
}
