import SwiftUI
import CuelistCompilerKit

/// Reusable aqua tap-to-talk button. Drives the shared VoiceCaptureController.
/// `fullWidth` = full-bleed pill; `showIcon` toggles the mic glyph; `compact`
/// = bottom-cluster trio styling (short "Talk"/"Stop" label, size-13 text).
struct VoiceButton: View {
    @Environment(ProjectStore.self) private var store
    @Environment(VoiceCaptureController.self) private var voice
    var fullWidth: Bool = true
    var showIcon: Bool = true
    var compact: Bool = false

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
            HStack(spacing: compact ? 6 : 10) {
                if voice.phase.isBusy {
                    ProgressView().tint(Theme.aquaInk)
                } else {
                    if showIcon {
                        Image(systemName: voice.phase.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: compact ? 15 : 18, weight: .bold))
                            .symbolEffect(.pulse, isActive: voice.phase.isRecording)
                    }
                    Text(compact ? voice.phase.talkButtonLabel : voice.phase.talkBarLabel)
                        .font(.system(size: compact ? 13 : 16, weight: .bold)).lineLimit(1)
                }
            }
            .foregroundStyle(Theme.aquaInk)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, fullWidth ? 16 : 14)
            .background(Theme.aquaGradient, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .shadow(color: Theme.aqua.opacity(0.5), radius: compact ? 12 : (fullWidth ? 22 : 12), y: 4)
            .opacity(voice.phase.isBusy ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(voice.phase.isBusy)
    }
}
