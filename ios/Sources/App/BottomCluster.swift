import SwiftUI
import CuelistCompilerKit

/// Pinned bottom trio on the Author tab: Add Cue (violet) · Note (aqua) · Talk (aqua).
struct BottomCluster: View {
    let onAddCue: () -> Void
    let onNote: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAddCue) {
                clusterLabel("Add Cue", symbol: "plus", ink: .white)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                    .shadow(color: Theme.accentSolid.opacity(0.4), radius: 12, y: 3)
            }
            .buttonStyle(.plain)

            Button(action: onNote) {
                clusterLabel("Note", symbol: "square.and.pencil", ink: Theme.aqua)
                    .background(Theme.aquaTint, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
                        .strokeBorder(Theme.aqua.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(.plain)

            VoiceButton(fullWidth: true, showLabel: false)
        }
        .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
    }

    private func clusterLabel(_ text: String, symbol: String, ink: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold))
            Text(text).font(.system(size: 13, weight: .bold)).lineLimit(1)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity).padding(.vertical, 16)
    }
}
