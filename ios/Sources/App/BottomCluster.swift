import SwiftUI
import SaettaKit

/// Pinned bottom trio on the Author tab: Add Cue (amber, dark ink) · Note · Talk (pale amber).
struct BottomCluster: View {
    let onAddCue: () -> Void
    let onNote: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAddCue) {
                clusterLabel("Add Cue", ink: Theme.aquaInk)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                    .shadow(color: Theme.accentSolid.opacity(0.4), radius: 12, y: 3)
            }
            .buttonStyle(.plain)

            Button(action: onNote) {
                clusterLabel("Note", ink: Theme.aqua)
                    .background(Theme.aquaTint, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
                        .strokeBorder(Theme.aqua.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(.plain)

            VoiceButton(fullWidth: true, showIcon: false, compact: true)
        }
        .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
    }

    private func clusterLabel(_ text: String, ink: Color) -> some View {
        Text(text).font(.system(size: 13, weight: .bold)).lineLimit(1)
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
    }
}
