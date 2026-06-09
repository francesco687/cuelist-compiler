// Sources/App/Fixture/PresetRecallGrid.swift
import SwiftUI
import SaettaKit

/// A grid of numbered preset-recall buttons for a pool. Tapping slot N fires
/// "At Preset <pool>.N". Slot count is fixed; labels are not read from the desk.
struct PresetRecallGrid: View {
    let pool: Pool
    let slots: Int                 // how many numbered buttons to show
    let onRecall: (Int) -> Void    // preset number tapped

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(slots >= 1 ? Array(1...slots) : [], id: \.self) { n in
                    Button { onRecall(n) } label: {
                        VStack(spacing: 2) {
                            Text("\(pool.number).\(n)")
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                                .foregroundStyle(Theme.text)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border, lineWidth: 0.5))
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            .padding(.vertical, 4)
        }
    }
}
