import SwiftUI
import CuelistCompilerKit

/// Full-width aqua tap-to-talk bar at the bottom of the screen. Drives the
/// existing VoiceCaptureController; the preview/error UI is owned by RootView.
struct TalkBarView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(VoiceCaptureController.self) private var voice

    var body: some View {
        Button {
            Task {
                if voice.phase.isRecording {
                    await voice.stopAndProcess(project: store.project, defaults: store.defaults)
                } else {
                    await voice.startRecording()
                }
            }
        } label: {
            HStack(spacing: 10) {
                if voice.phase.isBusy {
                    ProgressView().tint(Theme.aquaInk)
                } else {
                    Image(systemName: voice.phase.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .bold))
                        .symbolEffect(.pulse, isActive: voice.phase.isRecording)
                }
                Text(voice.phase.talkBarLabel)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(Theme.aquaInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.aquaGradient, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .shadow(color: Theme.aqua.opacity(0.5), radius: 22, y: 4)
            .opacity(voice.phase.isBusy ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(voice.phase.isBusy)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 4)
    }
}
