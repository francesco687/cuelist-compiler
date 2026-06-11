// Sources/App/Fixture/JogFader.swift
import SwiftUI

/// A vertical jog strip that emits RELATIVE integer deltas as you drag up/down.
/// The grip springs back to center on release. Drag distance maps to deltas via
/// a points-per-unit factor (coarse vs fine). Accumulates a fractional residual
/// so slow drags still register whole-unit steps.
///
/// The track FILLS the available height (the parent decides how much room each
/// fader gets), so a single full-row fader is huge and a 2×2 grid fader is about
/// half-height — and the screen's bottom buttons never get pushed under the tab bar.
struct JogFader: View {
    let label: String
    let valueText: String          // running session offset, e.g. "+12"
    let fine: Bool
    let onNudge: (Int) -> Void     // incremental delta during drag
    let onEnd: () -> Void          // drag ended → flush
    let onReset: () -> Void        // double-tap → request reset (parent confirms)

    @State private var lastY: CGFloat = 0
    @State private var residual: CGFloat = 0
    @State private var gripOffset: CGFloat = 0
    @State private var tickCount = 0          // bumped per whole-unit step → detent haptic

    private var pointsPerUnit: CGFloat { fine ? 24 : 8 }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let h = geo.size.height
                let gripHeight = min(64, max(38, h * 0.28))   // big grip, scaled to the track
                let limit = max(0, h / 2 - gripHeight / 2)
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface2)
                        .overlay(TickGrid().clipShape(RoundedRectangle(cornerRadius: Theme.radius)))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border, lineWidth: 0.5))
                    Image(systemName: "chevron.up").font(.title3).foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 10)
                    Image(systemName: "chevron.down").font(.title3).foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 10)
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .fill(Theme.accentGradient)
                        .frame(height: gripHeight)
                        .padding(.horizontal, 6)
                        .shadow(color: Theme.accentSolid.opacity(0.5), radius: 8)
                        .offset(y: gripOffset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let dy = v.translation.height - lastY
                            lastY = v.translation.height
                            // Up (negative dy) = increase.
                            residual += -dy / pointsPerUnit
                            let whole = Int(residual.rounded(.towardZero))
                            if whole != 0 {
                                residual -= CGFloat(whole)
                                onNudge(whole)
                                tickCount &+= 1     // detent tick on each whole-unit step
                            }
                            gripOffset = max(-limit, min(limit, v.translation.height))
                        }
                        .onEnded { _ in
                            lastY = 0; residual = 0
                            withAnimation(.snappy(duration: 0.18)) { gripOffset = 0 }
                            onEnd()
                        }
                )
                // Double-tap requests a reset. Simultaneous so it coexists with the
                // zero-distance drag (a tap fires a harmless zero-delta drag too).
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded { onReset() }
                )
            }
            .frame(maxWidth: .infinity, minHeight: 90, maxHeight: .infinity)

            Text(label).font(Theme.mono(size: 13, weight: .semibold)).hudLabel().foregroundStyle(Theme.textDim)
            Text(valueText).font(Theme.mono(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
        }
        // Light "detent" tick as the value steps — picker-wheel feel, handles
        // rapid steps during a fast drag without feeling spammy.
        .sensoryFeedback(.selection, trigger: tickCount)
    }
}
