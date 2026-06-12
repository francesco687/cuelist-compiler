import SwiftUI

/// Single source of truth for the dark "Amber Aurora-Glass" look.
/// Monochrome: one hue (amber) throughout. Status signals by brightness + glyph,
/// NOT by hue — the one exception is `danger` (red), reserved for destructive delete.
enum Theme {
    // Accent — single amber (gradient #f0b860 → #e0913f), solid #eaa64f. The "commit to MA" action.
    static let accentStart = Color(hex: "#f0b860")!
    static let accentEnd   = Color(hex: "#e0913f")!
    static let accentSolid = Color(hex: "#eaa64f")!
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static let accentTint = Color(hex: "#f0b860")!.opacity(0.12)   // group-card fill
    static let accentBorder = Color(hex: "#f0b860")!.opacity(0.22) // glass hairline

    // Capture/voice accent (talk bar, notes). Monochrome: a PALE amber TONE — same hue
    // family as the accent, distinguished by lightness rather than a second colour, so
    // "capture/voice" still reads distinct from the saturated "commit to MA" amber.
    static let aqua = Color(hex: "#f5d8a6")!
    static var aquaGradient: RadialGradient {
        RadialGradient(colors: [Color(hex: "#ffe9c2")!, Color(hex: "#e8c074")!],
                       center: UnitPoint(x: 0.38, y: 0.28), startRadius: 2, endRadius: 220)
    }
    static let aquaTint = Color(hex: "#f5d8a6")!.opacity(0.10)
    static let aquaInk = Color(hex: "#2a1d07")!   // dark text/icon on pale-amber surfaces

    // Surfaces / borders (white over the dark canvas).
    static let surface1 = Color.white.opacity(0.05)
    static let surface2 = Color.white.opacity(0.07)
    static let surface3 = Color.white.opacity(0.10)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.14)

    // Text hierarchy — warm off-whites.
    static let text = Color(hex: "#f6ead6")!
    static let textDim = Color(hex: "#c2a079")!
    static let textFaint = Color(hex: "#94795e")!

    // Status — monochrome amber by brightness; glyphs carry meaning.
    static let ok = Color(hex: "#f0c074")!     // bright amber — live / success
    static let warn = Color(hex: "#d49a4a")!   // mid amber — delay numerics / connecting
    static let danger = Color(hex: "#ff6b6b")! // RED — destructive delete (kept as the affordance)
    static let execActive = Color(hex: "#4cd964")!   // green — executor believed active (Live pad stripe)
    static let execInactive = Color(hex: "#ff6b6b")! // red — executor believed inactive (danger's hue, distinct semantic)

    // Radii — tightened for the HUD look. Circular elements (CueBadge) are unaffected.
    static let radius: CGFloat = 7
    static let radiusSmall: CGFloat = 4
    static let radiusLarge: CGFloat = 11          // pill CTAs (bottom cluster, delete bar)

    /// HUD monospace face — real SF Mono, for every numeric readout and HUD label.
    /// (The app previously used only `.monospacedDigit()` on a proportional face.)
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Full-screen amber aurora canvas. Radial blooms over a near-black base.
    static var canvas: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#1d160e")!, Color(hex: "#15110a")!, Color(hex: "#0f0c07")!],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: "#7a4f1e")!.opacity(0.55), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(hex: "#5c3a16")!.opacity(0.5), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Frosted glass card: material + warm highlight + amber-tinted hairline + soft glow.
    func cardSurface(_ fill: Color = Theme.surface1, radius: CGFloat = Theme.radius,
                     glow: Bool = false) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                    .blendMode(.plusLighter).opacity(0.4)
            )
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.accentBorder, lineWidth: 1))
            .shadow(color: Theme.accentSolid.opacity(glow ? 0.35 : 0.16), radius: glow ? 18 : 12, y: 8)
    }

    /// Soft amber bloom for hero elements (send button, live dot).
    func accentGlow(_ strength: Double = 0.5) -> some View {
        self.shadow(color: Theme.accentSolid.opacity(strength), radius: 14, y: 3)
            .shadow(color: Theme.accentEnd.opacity(strength * 0.6), radius: 30, y: 0)
    }

    /// HUD section/control label: uppercase + letter-spacing. Pairs with `Theme.mono`.
    func hudLabel() -> some View {
        self.textCase(.uppercase).tracking(1.2)
    }
}

/// "Commit to MA" call-to-action: bright amber surface with DARK warm ink.
/// Dark ink (not white) is the legible choice on the light amber gradient.
/// `dim` lowers priority with a flatter, darker amber while staying in-family.
struct AmberCTAStyle: ButtonStyle {
    var dim = false
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrowtriangle.right.fill").font(.system(size: 9, weight: .bold))
                .accessibilityHidden(true)
            configuration.label
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.aquaInk)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background {
            if dim { Theme.accentEnd.opacity(0.85) } else { Theme.accentGradient }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .shadow(color: Theme.accentSolid.opacity(dim ? 0.18 : 0.32), radius: dim ? 4 : 6, y: 1)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
