import SwiftUI
import CuelistCompilerKit

struct ActionBlockView: View {
    @Environment(ProjectStore.self) private var store
    @Binding var cue: Cue
    @Binding var action: Action
    @State private var showColors = false
    @State private var revealed: Set<Pool> = []

    private var blockIndex: Int? { cue.actions.firstIndex(where: { $0.id == action.id }) }

    private func isEmpty(_ pool: Pool) -> Bool {
        let p = action.presets[pool] ?? Preset()
        return p.name.trimmingCharacters(in: .whitespaces).isEmpty
            && p.fade.trimmingCharacters(in: .whitespaces).isEmpty
            && p.delay.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // Shown rows = pools with content OR explicitly revealed this session, in canonical order.
    private var shownPools: [Pool] { Pool.allCases.filter { !isEmpty($0) || revealed.contains($0) } }
    private var emptyPools: [Pool] { Pool.allCases.filter { isEmpty($0) && !revealed.contains($0) } }

    private var accent: Color { Color(hex: action.color) ?? Theme.accentSolid }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button { showColors = true } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: action.color) ?? Theme.surface3)
                        .frame(width: 14, height: 14)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border, lineWidth: 1))
                }
                .popover(isPresented: $showColors) { ColorPickerPopover(selection: $action.color) }

                TextField("Group name", text: $action.group)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .autocorrectionDisabled()

                Button {
                    if let i = blockIndex { store.removeActionBlock(cueId: cue.id, at: i) }
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textFaint) }
                .buttonStyle(.plain)
            }

            ForEach(shownPools, id: \.self) { pool in
                PoolRowView(pool: pool, action: $action)
            }

            AddChips(pools: emptyPools) { pool in
                withAnimation(.snappy(duration: 0.18)) { _ = revealed.insert(pool) }
            }
            .padding(.top, 8)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accentTint))
        .overlay(
            HStack { Rectangle().fill(accent).frame(width: 3); Spacer() }
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}
