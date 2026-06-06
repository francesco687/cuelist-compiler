import SwiftUI
import SaettaKit

struct ColorPickerPopover: View {
    @Binding var selection: String          // "" = no color
    @Environment(\.dismiss) private var dismiss

    private let cols = Array(repeating: GridItem(.fixed(34), spacing: 8), count: 5)

    var body: some View {
        LazyVGrid(columns: cols, spacing: 8) {
            swatch(hex: "", isNone: true)
            ForEach(PoolDisplay.actionColors, id: \.self) { hex in swatch(hex: hex, isNone: false) }
        }
        .padding()
        .background(Theme.surface3)
        .presentationCompactAdaptation(.popover)
    }

    private func swatch(hex: String, isNone: Bool) -> some View {
        Circle()
            .fill(isNone ? Theme.surface3 : (Color(hex: hex) ?? .gray))
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(Theme.accentSolid, lineWidth: selection == hex ? 2 : 0))
            .overlay(isNone ? Image(systemName: "slash.circle").font(.caption) : nil)
            .onTapGesture { selection = hex; dismiss() }
    }
}
