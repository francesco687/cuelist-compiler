import SwiftUI
import CuelistCompilerKit

struct CueCardView: View {
    @Environment(ProjectStore.self) private var store
    @Binding var cue: Cue

    private var groupChips: [String] {
        cue.actions.map { $0.group.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var presetCount: Int {
        cue.actions.reduce(0) { acc, a in
            acc + Pool.allCases.filter { pool in
                let p = a.presets[pool] ?? Preset()
                return !p.name.trimmingCharacters(in: .whitespaces).isEmpty
            }.count
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { cue.collapsed.toggle() }
            } label: {
                HStack(spacing: 11) {
                    CueBadge(n: cue.n)
                    TextField("Cue name", text: $cue.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .autocorrectionDisabled()
                        .disabled(cue.collapsed)            // tap toggles when collapsed
                    Spacer(minLength: 4)
                    Button(role: .destructive) {
                        store.removeCue(id: cue.id)
                    } label: { Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Theme.danger) }
                    .buttonStyle(.plain)
                    Image(systemName: cue.collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption).foregroundStyle(Theme.textFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if cue.collapsed {
                if !groupChips.isEmpty || presetCount > 0 {
                    HStack(spacing: 7) {
                        ForEach(Array(groupChips.prefix(3).enumerated()), id: \.offset) { _, g in Chip(text: g) }
                        if presetCount > 0 {
                            Text("\(presetCount) preset\(presetCount == 1 ? "" : "s")")
                                .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                        }
                    }
                }
            } else {
                CopyFromBar(cue: $cue)
                ForEach($cue.actions) { $action in
                    ActionBlockView(cue: $cue, action: $action)
                }
                Button { store.addActionBlock(cueId: cue.id) } label: {
                    Label("Add group", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accentSolid)
                }
                .buttonStyle(.plain)

                HStack(spacing: 14) {
                    StepperField(label: "Fade", value: $cue.fade, tint: Theme.accentSolid)
                    StepperField(label: "Delay", value: $cue.delay, tint: Theme.warn)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(13)
        .cardSurface()
    }
}
