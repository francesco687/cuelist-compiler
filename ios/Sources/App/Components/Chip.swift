import SwiftUI

/// Small pill used in collapsed-cue summaries.
struct Chip: View {
    let text: String
    var tint: Color = Theme.text
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}
