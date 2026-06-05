import SwiftUI

/// Single source of truth for the dark "Tinted Vibrancy" look.
/// Values mirror the desktop's committed `web/css/styles.css :root` tokens
/// so iOS and desktop read as one product. If the desktop retunes, re-sync here.
enum Theme {
    // Accent — violet→blue gradient (#7a5cff → #5e8bff), solid fallback #6f78ff.
    static let accentStart = Color(hex: "#7a5cff")!
    static let accentEnd   = Color(hex: "#5e8bff")!
    static let accentSolid = Color(hex: "#6f78ff")!
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static let accentTint = Color(hex: "#7a5cff")!.opacity(0.12)   // group-card fill

    // Aqua — the iOS "capture/voice" accent (talk bar, notes). Distinct from the
    // violet→blue accent, which stays the "commit to MA" action. Tunable hex.
    static let aqua = Color(hex: "#21D4C4")!
    static var aquaGradient: RadialGradient {
        RadialGradient(colors: [Color(hex: "#3DF0DC")!, Color(hex: "#16C6B4")!],
                       center: UnitPoint(x: 0.38, y: 0.28), startRadius: 2, endRadius: 220)
    }
    static let aquaTint = Color(hex: "#21D4C4")!.opacity(0.10)

    // Surfaces / borders (white over the dark canvas).
    static let surface1 = Color.white.opacity(0.045)
    static let surface2 = Color.white.opacity(0.06)
    static let surface3 = Color.white.opacity(0.09)
    static let border = Color.white.opacity(0.075)
    static let borderStrong = Color.white.opacity(0.14)

    // Text hierarchy.
    static let text = Color(hex: "#e9eaf0")!
    static let textDim = Color(hex: "#9a9eaa")!
    static let textFaint = Color(hex: "#7c8090")!

    // Semantic signals.
    static let ok = Color(hex: "#5fe08a")!            // live / online
    static let warn = Color(hex: "#f0b850")!          // delay numerics / connecting
    static let danger = Color(hex: "#ff6b6b")!        // destructive / error

    // Radii.
    static let radius: CGFloat = 11
    static let radiusSmall: CGFloat = 7

    /// Full-screen app canvas (radial dark gradient). Use as a background.
    static var canvas: some View {
        LinearGradient(colors: [Color(hex: "#1b1e26")!, Color(hex: "#15171c")!, Color(hex: "#111319")!],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

extension View {
    /// Standard translucent card: surface fill + hairline border + radius.
    func cardSurface(_ fill: Color = Theme.surface1, radius: CGFloat = Theme.radius) -> some View {
        self.background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.border, lineWidth: 0.5))
    }
}
