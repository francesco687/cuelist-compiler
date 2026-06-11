import SwiftUI
import SaettaKit

/// The Send tab — a full-page OSC send flow (replaces the old bottom SendBarView).
/// Violet accent family (Send→MA), distinct from the aqua capture family.
struct SendView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(HubClient.self) private var hub

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(spacing: 22) {
                    // Connection
                    Button { hub.connect() } label: {
                        HStack(spacing: 10) {
                            LiveIndicator(state: hub.state)
                            Spacer()
                            Text(hub.state.isOnline ? "Connected" : "Tap to connect")
                                .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                        }
                        .padding(.vertical, 12).padding(.horizontal, 14)
                        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Store mode
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Store mode").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textDim)
                        Picker("Store", selection: $store.project.storeMode) {
                            ForEach(StoreMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Three decoupled send actions
                    VStack(spacing: 14) {
                        sendRow(title: "Send Cues", systemImage: "paperplane.fill", primary: true) {
                            hub.sendCues(project: store.project, defaults: store.defaults, selection: .current)
                        } allAction: {
                            hub.sendCues(project: store.project, defaults: store.defaults, selection: .all)
                        }

                        sendRow(title: "Send Notes", systemImage: "square.and.pencil", primary: false) {
                            hub.sendNotes(project: store.project, selection: .current)
                        } allAction: {
                            hub.sendNotes(project: store.project, selection: .all)
                        }

                        // Matches sendRow chrome (icon + row), single button driven by ticked cues. Active song only, auto-clears after send.
                        timecodeRow
                    }
                    .disabled(!hub.state.isOnline)
                    .opacity(hub.state.isOnline ? 1 : 0.5)

                    resultRow
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Send to MA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var tickedCount: Int {
        guard let song = store.project.activeSong else { return 0 }
        return song.cues.filter { store.tcSelection.contains($0.id) && Smpte.isValid($0.position) }.count
    }

    private var canSendTimecode: Bool {
        store.project.activeSong != nil && tickedCount > 0
    }

    @ViewBuilder
    private func sendRow(title: String, systemImage: String, primary: Bool,
                         currentAction: @escaping () -> Void,
                         allAction: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: primary ? .semibold : .medium))
                .foregroundStyle(Theme.text)
            Spacer()
            Button("Current", action: currentAction)
                .buttonStyle(AmberCTAStyle(dim: !primary))
                .accessibilityLabel("\(title) – current song")
            Button("All Songs", action: allAction)
                .buttonStyle(.bordered)
                .tint(Theme.accentSolid)
                .accessibilityLabel("\(title) – all songs")
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    // Mirrors sendRow's container, but TC is a single ticked-driven action (no Current/All scope).
    @ViewBuilder private var timecodeRow: some View {
        HStack(spacing: 10) {
            Label("Send Timecode", systemImage: "timer")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text)
            Spacer()
            Button(tickedCount > 0 ? "Send (\(tickedCount))" : "Send") {
                if let song = store.project.activeSong {
                    hub.sendTimecode(song: song, ticked: store.tcSelection)
                    store.clearTcSelection()
                }
            }
            .buttonStyle(AmberCTAStyle())
            .disabled(!canSendTimecode)
            .accessibilityLabel("Send timecode – \(tickedCount) ticked cues")
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    @ViewBuilder private var resultRow: some View {
        if let p = hub.progress {
            VStack(spacing: 6) {
                ProgressView(value: Double(p.sent), total: Double(max(1, p.total))).tint(Theme.accentSolid)
                Text("sending \(p.sent)/\(p.total)\u{2026}").font(.system(size: 12)).foregroundStyle(Theme.textDim)
            }
        } else if let result = hub.lastResult {
            switch result {
            case let .done(total):
                Label("Sent \(total) lines", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(Theme.ok)
            case let .failed(msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13)).foregroundStyle(Theme.danger)
            }
        }
    }
}
