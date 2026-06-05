import SwiftUI
import CuelistCompilerKit

@main
struct CuelistCompilerApp: App {
    @State private var store = ProjectStore()
    @State private var hub = HubClient(makeConnection: { url in
        URLSessionWebSocketConnection(url: url)
    })
    @State private var voice = VoiceCaptureController(
        recorder: AVAudioFileRecorder(),
        transcriber: WhisperTranscriber(apiKey: KeychainAIKeyStore().key(for: .openAI) ?? ""),
        interpreter: AnthropicInterpreter(apiKey: KeychainAIKeyStore().key(for: .anthropic) ?? "")
    )
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(hub)
                .environment(voice)
                .onAppear { if !hub.host.isEmpty { hub.connect() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveNow() }
        }
    }
}
