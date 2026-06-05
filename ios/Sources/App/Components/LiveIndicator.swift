import SwiftUI
import CuelistCompilerKit

/// Hub connection signal: green dot = online ("linked"), amber = connecting,
/// red = error, faint = offline. Mirrors desktop's --ok green.
struct LiveIndicator: View {
    let state: ConnectionState
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.9), radius: 5)
            Text(label).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(color)
    }
    private var color: Color {
        switch state {
        case .offline: return Theme.textFaint
        case .connecting: return Theme.warn
        case .online: return Theme.ok
        case .error: return Theme.danger
        }
    }
    private var label: String {
        switch state {
        case .offline: return "offline"
        case .connecting: return "connecting…"
        case .online: return "linked"
        case let .error(m): return m
        }
    }
}
