import SwiftUI
import UIKit
import SaettaKit

@main
struct SaettaApp: App {
    @State private var store = ProjectStore()
    @State private var hub = HubClient(makeConnection: { url in
        URLSessionWebSocketConnection(url: url)
    })
    @State private var macroPad = MacroPad()
    @State private var voice = VoiceCaptureController(
        recorder: AVAudioFileRecorder(),
        transcriber: WhisperTranscriber(apiKey: KeychainAIKeyStore().key(for: .openAI) ?? ""),
        interpreter: AnthropicInterpreter(apiKey: KeychainAIKeyStore().key(for: .anthropic) ?? "")
    )
    // Note capture shares the device audio session with `voice`; the UI never records both at once.
    @State private var notes = NotesCaptureController(
        recorder: AVAudioFileRecorder(),
        transcriber: WhisperTranscriber(apiKey: KeychainAIKeyStore().key(for: .openAI) ?? ""),
        router: AnthropicNoteRouter(apiKey: KeychainAIKeyStore().key(for: .anthropic) ?? "")
    )
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(hub)
                .environment(macroPad)
                .environment(voice)
                .environment(notes)
                .tint(Theme.accentSolid)
                .preferredColorScheme(.dark)
                .onAppear {
                    hub.operatorName = UIDevice.current.name
                    if !hub.host.isEmpty || hub.mode == .relay { hub.connect() }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveNow() }
        }
    }
}
