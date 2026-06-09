// Sources/App/Fixture/JogFader.swift
import SwiftUI

/// A vertical jog strip that emits RELATIVE integer deltas as you drag up/down.
/// The grip springs back to center on release. Drag distance maps to deltas via
/// a points-per-unit factor (coarse vs fine). Accumulates a fractional residual
/// so slow drags still register whole-unit steps.
struct JogFader: View {
    let label: String
    let valueText: String          // running session offset, e.g. "+12°"
    let fine: Bool
    let onNudge: (Int) -> Void     // incremental delta during drag
    let onEnd: () -> Void          // drag ended → flush

    @State private var lastY: CGFloat = 0
    @State private var residual: CGFloat = 0
    @State private var gripOffset: CGFloat = 0

    private var pointsPerUnit: CGFloat { fine ? 24 : 8 }
    private let trackHeight: CGFloat = 170
    private let gripHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.surface2)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border, lineWidth: 0.5))
                Image(systemName: "chevron.up").font(.caption).foregroundStyle(Theme.textFaint)
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 8)
                Image(systemName: "chevron.down").font(.caption).foregroundStyle(Theme.textFaint)
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 8)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.accentGradient)
                    .frame(height: gripHeight)
                    .shadow(color: Theme.accentSolid.opacity(0.5), radius: 8)
                    .offset(y: gripOffset)
            }
            .frame(width: 52, height: trackHeight)
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

            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
            Text(valueText).font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.text)
        }
    }
}
