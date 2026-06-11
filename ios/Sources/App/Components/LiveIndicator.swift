import SwiftUI
import CuelistCompilerKit

/// Hub connection signal, monochrome amber by BRIGHTNESS (not hue):
/// offline = dim hollow dot, connecting = mid amber, online = full bright glowing dot.
/// Error reuses the dim treatment with the message text — no red here (red is delete-only).
struct LiveIndicator: View {
    let state: ConnectionState
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.isOnline ? Theme.ok : dotColor.opacity(0.0))
                .overlay(Circle().strokeBorder(dotColor, lineWidth: state.isOnline ? 0 : 1.5))
                .frame(width: 8, height: 8)
                .shadow(color: Theme.ok.opacity(state.isOnline ? 0.9 : 0), radius: 5)
            Text(label).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(textColor)
    }
    private var dotColor: Color {
        switch state {
        case .offline: return Theme.textFaint
        case .connecting: return Theme.warn
        case .online: return Theme.ok
        case .error: return Theme.textDim
        }
    }
    private var textColor: Color { state.isOnline ? Theme.ok : Theme.textDim }
    private var label: String {
        switch state {
        case .offline: return "offline"
        case .connecting: return "connecting…"
        case .online: return "linked"
        case let .error(m): return m
        }
    }
}
