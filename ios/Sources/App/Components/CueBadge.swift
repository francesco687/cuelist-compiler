import SwiftUI

/// Gradient rounded badge showing a cue number.
struct CueBadge: View {
    let n: Double
    var body: some View {
        Text(n, format: .number)
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .shadow(color: Theme.accentSolid.opacity(0.45), radius: 8, y: 2)
    }
}
