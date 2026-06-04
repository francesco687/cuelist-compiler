import SwiftUI
import CuelistCompilerKit

struct ActionBlockView: View {
    @Environment(ProjectStore.self) private var store
    @Binding var cue: Cue
    @Binding var action: Action
    @State private var showColors = false

    private var blockIndex: Int? { cue.actions.firstIndex(where: { $0.id == action.id }) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    showColors = true
                } label: {
                    Circle()
                        .fill(Color(hex: action.color) ?? Color(.systemGray4))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.secondary, lineWidth: 1))
                }
                .popover(isPresented: $showColors) { ColorPickerPopover(selection: $action.color) }

                TextField("Group name", text: $action.group).textFieldStyle(.roundedBorder)

                Button(role: .destructive) {
                    if let i = blockIndex { store.removeActionBlock(cueId: cue.id, at: i) }
                } label: { Image(systemName: "xmark.circle") }
            }
            ForEach(Pool.allCases, id: \.self) { pool in
                PoolRowView(pool: pool, action: $action)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
    }
}
