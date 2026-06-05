import SwiftUI
import CuelistCompilerKit

struct RootView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(VoiceCaptureController.self) private var voice
    @State private var showSettings = false
    @State private var showDefaults = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SongBarView()
                CueListView()
                SendBarView()
            }
            .navigationTitle("Cuelist Compiler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { micButton }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Defaults…") { showDefaults = true }
                        Button("Settings…") { showSettings = true }
                    } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showDefaults) { DefaultsView() }
            .sheet(isPresented: previewBinding) {
                if let pending = voice.pending {
                    VoicePreviewSheet(
                        pending: pending,
                        onApply: { store.apply(pending.result); voice.cancel() },
                        onDiscard: { voice.cancel() }
                    )
                }
            }
            .alert("Voice", isPresented: errorBinding) {
                Button("OK") { voice.cancel() }
            } message: { Text(errorText) }
        }
    }

    @ViewBuilder private var micButton: some View {
        switch voice.phase {
        case .idle, .error:
            Button { Task { await voice.startRecording() } } label: { Image(systemName: "mic") }
        case .recording:
            Button {
                Task { await voice.stopAndProcess(project: store.project, defaults: store.defaults) }
            } label: { Image(systemName: "stop.circle.fill").foregroundStyle(.red) }
        case .transcribing, .interpreting:
            ProgressView()
        case .preview:
            Image(systemName: "mic").foregroundStyle(.secondary)
        }
    }

    private var previewBinding: Binding<Bool> {
        Binding(get: { if case .preview = voice.phase { return true } else { return false } },
                set: { if !$0 { voice.cancel() } })
    }
    private var errorBinding: Binding<Bool> {
        Binding(get: { if case .error = voice.phase { return true } else { return false } },
                set: { if !$0 { voice.cancel() } })
    }
    private var errorText: String {
        if case let .error(m) = voice.phase { return m } else { return "" }
    }
}
