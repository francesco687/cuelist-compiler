import SwiftUI

/// Faint repeating horizontal hairlines — HUD "tick grid" texture behind fader
/// tracks and readout strips. Amber at low opacity so it reads as instrumentation,
/// not chrome. Non-interactive.
struct TickGrid: View {
    var spacing: CGFloat = 24
    var body: some View {
        GeometryReader { geo in
            Path { p in
                guard spacing > 0 else { return }
                var y = spacing
                while y < geo.size.height {
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    y += spacing
                }
            }
            .stroke(Theme.accentStart.opacity(0.07), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// Four L-shaped corner brackets framing a panel — the signature HUD element.
/// Drawn as an overlay; non-interactive.
struct CornerBrackets: View {
    var color: Color = Theme.accentSolid
    var length: CGFloat = 14
    var lineWidth: CGFloat = 2
    var inset: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                // top-left
                p.move(to: CGPoint(x: inset, y: inset + length))
                p.addLine(to: CGPoint(x: inset, y: inset))
                p.addLine(to: CGPoint(x: inset + length, y: inset))
                // top-right
                p.move(to: CGPoint(x: w - inset - length, y: inset))
                p.addLine(to: CGPoint(x: w - inset, y: inset))
                p.addLine(to: CGPoint(x: w - inset, y: inset + length))
                // bottom-left
                p.move(to: CGPoint(x: inset, y: h - inset - length))
                p.addLine(to: CGPoint(x: inset, y: h - inset))
                p.addLine(to: CGPoint(x: inset + length, y: h - inset))
                // bottom-right
                p.move(to: CGPoint(x: w - inset - length, y: h - inset))
                p.addLine(to: CGPoint(x: w - inset, y: h - inset))
                p.addLine(to: CGPoint(x: w - inset, y: h - inset - length))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Hero HUD panel: the existing frosted `cardSurface` + corner brackets.
    func hudPanel(_ fill: Color = Theme.surface1,
                  radius: CGFloat = Theme.radius,
                  glow: Bool = false) -> some View {
        self
            .cardSurface(fill, radius: radius, glow: glow)
            .overlay(CornerBrackets())
    }
}
