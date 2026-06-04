import SwiftUI
import CuelistCompilerKit

struct SendBarView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(HubClient.self) private var hub

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 6) {
            HStack {
                pill
                Spacer()
                Picker("Store", selection: $store.project.storeMode) {
                    ForEach(StoreMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 180)
            }
            HStack(spacing: 10) {
                Button {
                    hub.send(project: store.project, defaults: store.defaults, selection: .current)
                } label: { Label("Send current", systemImage: "paperplane") }
                    .buttonStyle(.borderedProminent)
                Button {
                    hub.send(project: store.project, defaults: store.defaults, selection: .all)
                } label: { Label("Send all", systemImage: "paperplane.fill") }
                    .buttonStyle(.bordered)
            }
            .disabled(!hub.state.isOnline)

            if let p = hub.progress {
                ProgressView(value: Double(p.sent), total: Double(max(1, p.total)))
                Text("sending \(p.sent)/\(p.total)…").font(.caption2).foregroundStyle(.secondary)
            } else if let result = hub.lastResult {
                switch result {
                case let .done(total):
                    Label("Sent \(total) lines", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.green)
                case let .failed(msg):
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private var pill: some View {
        Button {
            hub.connect()
        } label: {
            switch hub.state {
            case .offline:    Label("hub offline", systemImage: "circle").foregroundStyle(.secondary)
            case .connecting: Label("connecting…", systemImage: "circle.dotted").foregroundStyle(.orange)
            case .online:     Label("hub online", systemImage: "circle.fill").foregroundStyle(.green)
            case let .error(m): Label(m, systemImage: "circle.fill").foregroundStyle(.red)
            }
        }
        .font(.caption).lineLimit(1)
    }
}
