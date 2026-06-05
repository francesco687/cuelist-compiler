import SwiftUI
import CuelistCompilerKit

/// "Pull from MA" — asks the hub for the sequence list in the loaded showfile
/// and shows it, searchable. Display-only for now (picking a sequence to pull its
/// cues is a later phase). Styled to the "Tinted Vibrancy" theme.
struct PullSequencesView: View {
    @Environment(HubClient.self) private var hub
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                content
            }
            .navigationTitle("Pull from MA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }.foregroundStyle(Theme.textDim)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { hub.pullSequences() } label: { Image(systemName: "arrow.clockwise") }
                        .foregroundStyle(Theme.accentSolid)
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
            status("wifi.slash", "Hub offline", "Connect to the hub first, then pull.", Theme.textFaint)
        } else if hub.isPulling, hub.sequences == nil {
            spinner
        } else if let err = hub.pullError, hub.sequences == nil {
            status("exclamationmark.triangle.fill", "Pull failed", err, Theme.danger)
        } else if let seqs = hub.sequences {
            list(seqs)
        } else {
            spinner
        }
    }

    private var spinner: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Theme.accentSolid)
            Text("Pulling from MA…").font(.system(size: 13)).foregroundStyle(Theme.textDim)
        }
    }

    private func list(_ seqs: [PulledSequence]) -> some View {
        let shown = filter(seqs)
        return List {
            Section {
                ForEach(shown) { seq in
                    HStack(spacing: 12) {
                        Text(number(seq))
                            .font(.system(size: 13, weight: .medium, design: .monospaced).monospacedDigit())
                            .foregroundStyle(Theme.accentSolid)
                            .frame(minWidth: 56, alignment: .leading)
                        Text(seq.name.isEmpty ? "—" : seq.name)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.text)
                        Spacer()
                    }
                    .listRowBackground(Theme.surface1)
                    .listRowSeparatorTint(Theme.border)
                }
            } header: {
                Text(shown.count == seqs.count ? "\(seqs.count) sequences" : "\(shown.count) of \(seqs.count)")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textFaint)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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

    private func status(_ symbol: String, _ title: String, _ message: String, _ tint: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(tint)
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
            Text(message).font(.system(size: 13)).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }
}
