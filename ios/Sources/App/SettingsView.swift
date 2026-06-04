import SwiftUI
import CuelistCompilerKit

struct SettingsView: View {
    @Environment(HubClient.self) private var hub
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var hub = hub
        NavigationStack {
            Form {
                Section("Hub") {
                    TextField("Host (Pi LAN or tailnet IP)", text: $hub.host)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Port", value: $hub.port, format: .number)
                        .keyboardType(.numberPad)
                    Button("Connect") { hub.connect() }
                }
                Section {
                    LabeledContent("Status") { Text(statusText) }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var statusText: String {
        switch hub.state {
        case .offline: return "offline"
        case .connecting: return "connecting…"
        case .online: return "online"
        case let .error(m): return "error: \(m)"
        }
    }
}
