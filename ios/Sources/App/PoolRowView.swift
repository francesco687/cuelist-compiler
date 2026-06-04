import SwiftUI
import CuelistCompilerKit

struct PoolRowView: View {
    @Environment(ProjectStore.self) private var store
    let pool: Pool
    @Binding var action: Action

    private var binding: Binding<Preset> {
        Binding(get: { action.presets[pool] ?? Preset() },
                set: { action.presets[pool] = $0 })
    }

    var body: some View {
        let preset = binding
        HStack(spacing: 6) {
            Text(pool.abbreviation)
                .font(.caption2).bold()
                .frame(width: 34, alignment: .leading)
                .foregroundStyle(Color(hex: pool.accentHex) ?? .secondary)
            TextField("(none)", text: preset.name).textFieldStyle(.roundedBorder)
            TextField(store.defaults.fade(pool).isEmpty ? "f" : store.defaults.fade(pool),
                      text: preset.fade)
                .textFieldStyle(.roundedBorder).frame(width: 40).keyboardType(.decimalPad)
            TextField(store.defaults.delay(pool).isEmpty ? "d" : store.defaults.delay(pool),
                      text: preset.delay)
                .textFieldStyle(.roundedBorder).frame(width: 40).keyboardType(.decimalPad)
        }
    }
}
