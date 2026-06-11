import SwiftUI

/// Small frosted pill used in collapsed-cue summaries.
struct Chip: View {
    let text: String
    var tint: Color = Theme.textDim
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.accentBorder, lineWidth: 1))
    }
}
