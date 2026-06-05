import SwiftUI
import CuelistCompilerKit

struct DefaultsView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Default fade / delay") {
                    Text("Used at send when a preset's own fade/delay is blank. Shown as placeholders in the cue editor.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Pool.allCases, id: \.self) { pool in
                        HStack {
                            Text(pool.rawValue.capitalized).frame(width: 90, alignment: .leading)
                            TextField("fade", text: bindingFade(pool))
                                .textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                            TextField("delay", text: bindingDelay(pool))
                                .textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                        }
                    }
                }
            }
            .navigationTitle("Defaults")
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .tint(Theme.accentSolid)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func bindingFade(_ pool: Pool) -> Binding<String> {
        Binding(get: { store.defaults.values[pool]?.fade ?? "" },
                set: { var p = store.defaults.values[pool] ?? Preset(); p.fade = $0; store.defaults.values[pool] = p })
    }
    private func bindingDelay(_ pool: Pool) -> Binding<String> {
        Binding(get: { store.defaults.values[pool]?.delay ?? "" },
                set: { var p = store.defaults.values[pool] ?? Preset(); p.delay = $0; store.defaults.values[pool] = p })
    }
}
