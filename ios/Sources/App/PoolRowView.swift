import SwiftUI
import SaettaKit

struct PoolRowView: View {
    @Environment(ProjectStore.self) private var store
    let pool: Pool
    @Binding var action: Action
    @State private var expanded = false

    private var preset: Binding<Preset> {
        Binding(get: { action.presets[pool] ?? Preset() },
                set: { action.presets[pool] = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Circle().fill(Color(hex: pool.accentHex) ?? .gray).frame(width: 8, height: 8)
                    Text(pool.abbreviation)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.text).frame(width: 32, alignment: .leading)
                    Text(preset.wrappedValue.name.isEmpty ? "—" : preset.wrappedValue.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(preset.wrappedValue.name.isEmpty ? Theme.textFaint : Theme.text)
                        .lineLimit(1)
                    Spacer()
                    fadeDelayLabel
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(Theme.textFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                editor.padding(.top, 8)
            }
        }
        .padding(.vertical, 9)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Theme.border), alignment: .top)
    }

    // Compact fade/delay readout: fade in accent, delay in warn. Falls back to the
    // per-pool default (shown dimmed) when the preset's own value is blank.
    @ViewBuilder private var fadeDelayLabel: some View {
        let f = preset.wrappedValue.fade
        let d = preset.wrappedValue.delay
        let fShown = f.isEmpty ? store.defaults.fade(pool) : f
        let dShown = d.isEmpty ? store.defaults.delay(pool) : d
        if !fShown.isEmpty || !dShown.isEmpty {
            HStack(spacing: 3) {
                Text(fShown.isEmpty ? "–" : fShown)
                    .foregroundStyle(f.isEmpty ? Theme.accentSolid.opacity(0.45) : Theme.accentSolid)
                Text("/").foregroundStyle(Theme.textFaint)
                Text(dShown.isEmpty ? "–" : dShown)
                    .foregroundStyle(d.isEmpty ? Theme.warn.opacity(0.45) : Theme.warn)
            }
            .font(.system(size: 11).monospacedDigit())
        }
    }

    private var editor: some View {
        VStack(spacing: 8) {
            TextField("preset name", text: preset.name)
                .font(.system(size: 13))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.border, lineWidth: 0.5))
                .autocorrectionDisabled()
            HStack(spacing: 14) {
                StepperField(label: "Fade", value: preset.fade,
                             placeholder: store.defaults.fade(pool), tint: Theme.accentSolid)
                StepperField(label: "Delay", value: preset.delay,
                             placeholder: store.defaults.delay(pool), tint: Theme.warn)
                Spacer()
            }
        }
    }
}
