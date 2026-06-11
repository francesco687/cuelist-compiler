import SwiftUI

/// Circular amber ring badge showing a cue number.
struct CueBadge: View {
    let n: Double
    var body: some View {
        Text(n, format: .number)
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                Circle().fill(
                    AngularGradient(colors: [Theme.accentStart, Theme.accentEnd, Theme.accentStart],
                                    center: .center, angle: .degrees(220)))
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 4))
            .shadow(color: Theme.accentSolid.opacity(0.5), radius: 10, y: 2)
    }
}
