import SwiftUI
import SaettaKit

struct SendBarView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(HubClient.self) private var hub

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 8) {
            HStack {
                Button { hub.connect() } label: { LiveIndicator(state: hub.state) }
                    .buttonStyle(.plain)
                Spacer()
                Picker("Store", selection: $store.project.storeMode) {
                    ForEach(StoreMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            HStack(spacing: 10) {
                Button {
                    hub.send(project: store.project, defaults: store.defaults, selection: .current)
                } label: {
                    Label("Send → MA", systemImage: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .foregroundStyle(Color(hex: "#0c0c14")!)
                        .accentGlow(0.55)
                }
                Button {
                    hub.send(project: store.project, defaults: store.defaults, selection: .all)
                } label: {
                    Text("All")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.vertical, 11).padding(.horizontal, 18)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .foregroundStyle(Theme.text)
                }
            }
            .buttonStyle(.plain)
            .disabled(!hub.state.isOnline)
            .opacity(hub.state.isOnline ? 1 : 0.5)

            resultRow
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .background(Theme.accentTint)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.accentBorder), alignment: .top)
    }

    @ViewBuilder private var resultRow: some View {
        if let p = hub.progress {
            VStack(spacing: 4) {
                ProgressView(value: Double(p.sent), total: Double(max(1, p.total))).tint(Theme.accentSolid)
                Text("sending \(p.sent)/\(p.total)…").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
        } else if let result = hub.lastResult {
            switch result {
            case let .done(total):
                Label("Sent \(total) lines", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.ok)
            case let .failed(msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textDim)
            }
        }
    }
}
