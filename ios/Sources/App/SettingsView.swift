import SwiftUI
import SaettaKit

struct SettingsView: View {
    @Environment(HubClient.self) private var hub
    @Environment(\.dismiss) private var dismiss

    private let keyStore = KeychainAIKeyStore()
    @State private var openAIKey = ""
    @State private var anthropicKey = ""

    var body: some View {
        @Bindable var hub = hub
        NavigationStack {
            Form {
                Section("Connection") {
                    Picker("Mode", selection: $hub.mode) {
                        Text("Direct (same WiFi)").tag(HubMode.direct)
                        Text("Relay (internet)").tag(HubMode.relay)
                    }
                    .pickerStyle(.segmented)

                    if hub.mode == .direct {
                        TextField("Host (laptop/Pi LAN IP)", text: $hub.host)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        TextField("Port", value: $hub.port, format: .number)
                            .keyboardType(.numberPad)
                    } else {
                        TextField("Relay URL", text: $hub.relayURL)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        TextField("Pairing code (from the laptop)", text: $hub.pairingCode)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    Button("Connect") { hub.connect() }
                }
                Section {
                    LabeledContent("Status") { Text(statusText) }
                }
                Section {
                    SecureField("OpenAI API key", text: $openAIKey)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    SecureField("Anthropic API key", text: $anthropicKey)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                } header: {
                    Text("Voice (API keys)")
                } footer: {
                    Text("Stored in your device Keychain. Voice commands send audio to OpenAI and the show context to Anthropic over HTTPS. After entering keys for the first time, relaunch the app.")
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .tint(Theme.accentSolid)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { saveKeys(); dismiss() }
                }
            }
            .onAppear {
                openAIKey = keyStore.key(for: .openAI) ?? ""
                anthropicKey = keyStore.key(for: .anthropic) ?? ""
                if hub.relayURL.isEmpty { hub.relayURL = "wss://cuelist-relay.fly.dev" }
            }
        }
    }

    private func saveKeys() {
        keyStore.set(openAIKey, for: .openAI)
        keyStore.set(anthropicKey, for: .anthropic)
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
