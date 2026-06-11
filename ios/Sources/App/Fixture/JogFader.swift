// Sources/App/Fixture/JogFader.swift
import SwiftUI

/// A vertical jog strip that emits RELATIVE integer deltas as you drag up/down.
/// The grip springs back to center on release. Drag distance maps to deltas via
/// a points-per-unit factor (coarse vs fine). Accumulates a fractional residual
/// so slow drags still register whole-unit steps.
struct JogFader: View {
    let label: String
    let valueText: String          // running session offset, e.g. "+12"
    let fine: Bool
    var height: CGFloat = 250      // track height — shorter for grid (2×2) layouts
    let onNudge: (Int) -> Void     // incremental delta during drag
    let onEnd: () -> Void          // drag ended → flush
    let onReset: () -> Void        // double-tap → request reset (parent confirms)

    @State private var lastY: CGFloat = 0
    @State private var residual: CGFloat = 0
    @State private var gripOffset: CGFloat = 0
    @State private var tickCount = 0          // bumped per whole-unit step → detent haptic

    private var pointsPerUnit: CGFloat { fine ? 24 : 8 }
    // Sized for fat-finger / thumb use: tall throw + a big grip. The track fills
    // the available width (so a single fader is huge, 3-up stays ~100pt each).
    // `height` is caller-controlled so grid (2×2) layouts can use shorter faders.
    private var trackHeight: CGFloat { height }
    private var gripHeight: CGFloat { min(64, height * 0.34) }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Theme.surface2)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 0.5))
                Image(systemName: "chevron.up").font(.title3).foregroundStyle(Theme.textFaint)
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 10)
                Image(systemName: "chevron.down").font(.title3).foregroundStyle(Theme.textFaint)
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 10)
                RoundedRectangle(cornerRadius: 11)
                    .fill(Theme.accentGradient)
                    .frame(height: gripHeight)
                    .padding(.horizontal, 6)
                    .shadow(color: Theme.accentSolid.opacity(0.5), radius: 8)
                    .offset(y: gripOffset)
            }
            .frame(maxWidth: .infinity, minHeight: trackHeight, maxHeight: trackHeight)
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
                        gripOffset = max(-trackHeight/2 + gripHeight/2,
                                         min(trackHeight/2 - gripHeight/2, v.translation.height))
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

            Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textDim)
            Text(valueText).font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.text)
        }
        // Light "detent" tick as the value steps — picker-wheel feel, handles
        // rapid steps during a fast drag without feeling spammy.
        .sensoryFeedback(.selection, trigger: tickCount)
    }
}
