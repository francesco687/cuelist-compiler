import SwiftUI
import SaettaKit

struct CueCardView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(NotesCaptureController.self) private var notes
    @Binding var cue: Cue
    @Environment(\.editMode) private var editMode
    @State private var confirmingDelete = false
    @State private var addingNote = false
    @State private var editingNote = false
    @State private var renumbering = false
    @State private var renumberText = ""

    private var isEditing: Bool { editMode?.wrappedValue == .active }

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
    private var tcValid: Bool { Smpte.isValid(cue.position) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { cue.collapsed.toggle() }
            } label: {
                HStack(spacing: 11) {
                    CueBadge(n: cue.n)
                        .onTapGesture {
                            renumberText = formatN(cue.n)
                            renumbering = true
                        }
                    TextField("Cue name", text: $cue.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .autocorrectionDisabled()
                        .disabled(cue.collapsed || isEditing)            // tap toggles when collapsed
                    Spacer(minLength: 4)
                    Image(systemName: cue.collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption).foregroundStyle(Theme.textFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!isEditing)

            if !cue.notes.isEmpty {
                Button { editingNote = true } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "square.and.pencil").font(.system(size: 10)).foregroundStyle(Theme.aqua)
                        Text(cue.notes).font(.system(size: 11)).foregroundStyle(Theme.text.opacity(0.85))
                            .lineLimit(cue.collapsed ? 2 : nil)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5).padding(.horizontal, 8)
                    .background(Theme.aquaTint, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    .overlay(Rectangle().frame(width: 2).foregroundStyle(Theme.aqua.opacity(0.5)), alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if cue.collapsed || isEditing {
                if !groupChips.isEmpty || presetCount > 0 {
                    HStack(spacing: 7) {
                        ForEach(Array(groupChips.prefix(3).enumerated()), id: \.offset) { _, g in Chip(text: g) }
                        if presetCount > 0 {
                            Text("\(presetCount) preset\(presetCount == 1 ? "" : "s")")
                                .font(Theme.mono(size: 12)).hudLabel().foregroundStyle(Theme.textDim)
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

                HStack(spacing: 10) {
                    Text("TC").font(Theme.mono(size: 11, weight: .medium)).hudLabel().foregroundStyle(Theme.textDim)
                    TextField("HH:MM:SS:FF", text: $cue.position)
                        .font(Theme.mono(size: 13))
                        .foregroundStyle(tcValid ? Theme.text : Theme.danger)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .frame(maxWidth: 130)
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        .onChange(of: cue.position) { _, newValue in
                            if !Smpte.isValid(newValue) { store.removeTc(cue.id) }
                        }
                    Spacer()
                    Button {
                        store.toggleTc(cue.id)
                    } label: {
                        Image(systemName: store.isTcSelected(cue.id) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundStyle(tcValid ? Theme.accentSolid : Theme.textFaint)
                    }
                    .buttonStyle(.plain)
                    .disabled(!tcValid)
                    .accessibilityLabel("Include timecode in Send Timecode")
                }
                .padding(.top, 4)

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
        .sheet(isPresented: $editingNote) { EditNoteView(cueN: cue.n, initialText: cue.notes) }
        .alert("Cue number", isPresented: $renumbering) {
            TextField("Number", text: $renumberText)
                .keyboardType(.decimalPad)
            Button("Save") {
                if let v = Double(renumberText.replacingOccurrences(of: ",", with: ".")) {
                    store.setCueNumber(id: cue.id, to: v)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Set the number for this cue.") }
        .padding(13)
        .cardSurface()
        .overlay(CornerBrackets(color: Theme.accentSolid.opacity(0.35), length: 10, lineWidth: 1.5))
    }
}
