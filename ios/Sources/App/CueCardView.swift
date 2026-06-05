import SwiftUI
import CuelistCompilerKit

struct CueCardView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(NotesCaptureController.self) private var notes
    @Binding var cue: Cue
    @State private var confirmingDelete = false
    @State private var addingNote = false

    private var cueLabel: String {
        let name = cue.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? formatN(cue.n) : "\(formatN(cue.n)) \"\(name)\""
    }
    private func formatN(_ n: Double) -> String {
        n.rounded() == n ? String(Int(n)) : String(n)
    }

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
                    Image(systemName: cue.collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption).foregroundStyle(Theme.textFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !cue.notes.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "square.and.pencil").font(.system(size: 10)).foregroundStyle(Theme.aqua)
                    Text(cue.notes).font(.system(size: 11)).foregroundStyle(Theme.text.opacity(0.85))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 5).padding(.horizontal, 8)
                .background(Theme.aquaTint, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(Rectangle().frame(width: 2).foregroundStyle(Theme.aqua.opacity(0.5)), alignment: .leading)
            }

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

                HStack {
                    Spacer()
                    Button { addingNote = true } label: {
                        Label("Note", systemImage: "square.and.pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.aqua)
                            .padding(.vertical, 6).padding(.horizontal, 11)
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                .strokeBorder(Theme.aqua.opacity(0.35), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete cue", systemImage: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.danger)
                            .padding(.vertical, 6).padding(.horizontal, 11)
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                .strokeBorder(Theme.danger.opacity(0.35), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
        }
        .confirmationDialog("Delete cue \(cueLabel)?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.removeCue(id: cue.id) }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $addingNote) { NotesCaptureView(targetCue: cue.n) }
        .padding(13)
        .cardSurface()
    }
}
