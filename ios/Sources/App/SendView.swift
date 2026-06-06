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

                    // Primary actions
                    VStack(spacing: 12) {
                        Button {
                            hub.send(project: store.project, defaults: store.defaults, selection: .current)
                        } label: {
                            Label("Send \u{2192} MA", systemImage: "paperplane.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.radius))
                                .foregroundStyle(.white)
                                .shadow(color: Theme.accentSolid.opacity(0.4), radius: 14, y: 3)
                        }
                        Button {
                            hub.send(project: store.project, defaults: store.defaults, selection: .all)
                        } label: {
                            Text("Send All Songs")
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius))
                                .foregroundStyle(Theme.text)
                        }
                    }
                    .buttonStyle(.plain)
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
