import SwiftUI
import SaettaKit

/// Dashed "＋POOL" chips for pools that are not yet shown. Tapping one reveals it.
struct AddChips: View {
    let pools: [Pool]
    let onAdd: (Pool) -> Void
    var body: some View {
        if !pools.isEmpty {
            HStack(spacing: 6) {
                ForEach(pools, id: \.self) { pool in
                    Button { onAdd(pool) } label: {
                        Text("＋ \(pool.abbreviation)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textDim)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                    .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [3]))
                            )
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
