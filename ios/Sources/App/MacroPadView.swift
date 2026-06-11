import SwiftUI
import SaettaKit

/// The Live tab's 2×2 macro pad. Each cell holds an assignable value that fires on
/// the desk through the hub's `cmd` passthrough: a parameter-free action (runs on
/// the desk-selected executor) or an executor toggle (Toggle Executor <n>, current
/// page). Tap empty → picker; tap assigned → fire; tap an unloaded executor → load
/// sheet; long-press assigned → load/reassign/clear.
struct MacroPadView: View {
    @Environment(MacroPad.self) private var pad
    @Environment(HubClient.self) private var hub
    let onFire: () -> Void                     // haptic trigger, shared with transport

    private struct SlotTarget: Identifiable { let id: Int }   // id == slot index
    @State private var picker: SlotTarget?
    @State private var execLoad: SlotTarget?

    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<MacroPad.slotCount, id: \.self) { slot in
                MacroButton(
                    slot: pad.slot(at: slot),
                    isOnline: hub.state.isOnline,
                    onTap: { handleTap(slot) },
                    onLoadExecutor: { execLoad = SlotTarget(id: slot) },
                    onReassign: { picker = SlotTarget(id: slot) },
                    onClear: { pad.clear(slot: slot) }
                )
            }
        }
        .sheet(item: $picker) { target in
            MacroPickerSheet(
                onPick: { action in
                    pad.assign(slot: target.id, action: action)
                    picker = nil
                },
                onPickExecutor: {
                    pad.assignExecutor(slot: target.id)
                    picker = nil
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $execLoad) { target in
            ExecutorLoadSheet(onLoad: { number in
                pad.loadExecutor(slot: target.id, number: number)
                execLoad = nil
            })
            .presentationDetents([.height(240)])
        }
    }

    private func handleTap(_ slot: Int) {
        switch pad.slot(at: slot) {
        case nil:
            picker = SlotTarget(id: slot)              // empty slot — assign even offline
        case .executor(number: nil):
            execLoad = SlotTarget(id: slot)            // step 2 of the double assign
        case let value?:
            guard hub.state.isOnline, let command = value.command else { return }
            hub.sendCommand(command)
            onFire()
        }
    }
}

/// One macro-pad cell, rendered per slot value:
/// action → tinted symbol + title; loaded executor → big number over EXEC caption;
/// unloaded executor → pending "EXEC —"; empty → dashed Assign placeholder.
private struct MacroButton: View {
    let slot: MacroSlot?
    let isOnline: Bool
    let onTap: () -> Void
    let onLoadExecutor: () -> Void
    let onReassign: () -> Void
    let onClear: () -> Void

    private var isExecutor: Bool {
        if case .executor = slot { return true }
        return false
    }

    /// Only slots that can actually fire dim when the hub is offline; the pending
    /// executor's tap opens the load sheet, which works offline.
    private var canFire: Bool { slot?.command != nil }

    var body: some View {
        if slot != nil {
            button.contextMenu {
                if isExecutor {
                    Button { onLoadExecutor() } label: { Label("Load Executor\u{2026}", systemImage: "number") }
                }
                Button { onReassign() } label: { Label("Reassign\u{2026}", systemImage: "arrow.triangle.2.circlepath") }
                Button(role: .destructive) { onClear() } label: { Label("Clear", systemImage: "xmark") }
            }
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: onTap) {
            content
                .frame(maxWidth: .infinity)
                .frame(height: 76)
        }
        .buttonStyle(PressScaleStyle())
        .opacity(canFire && !isOnline ? 0.4 : 1)
    }

    @ViewBuilder private var content: some View {
        switch slot {
        case .action(let action):
            VStack(spacing: 6) {
                Image(systemName: action.symbol).font(.system(size: 26, weight: .bold))
                Text(action.title).font(.system(size: 17, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.accentSolid.gradient, in: RoundedRectangle(cornerRadius: Theme.radius))
        case .executor(let number?):
            VStack(spacing: 2) {
                Text("\(number)").font(Theme.mono(size: 26, weight: .heavy))
                Text("EXEC").font(.system(size: 11, weight: .semibold)).opacity(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.accentSolid.gradient, in: RoundedRectangle(cornerRadius: Theme.radius))
        case .executor(nil):
            VStack(spacing: 2) {
                Text("\u{2014}").font(Theme.mono(size: 26, weight: .heavy))
                Text("EXEC").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            )
        case nil:
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 22, weight: .semibold))
                Text("Assign").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            )
        }
    }
}

/// Lists the executor option then the curated macro library; one tap assigns and
/// dismisses.
private struct MacroPickerSheet: View {
    let onPick: (MacroAction) -> Void
    let onPickExecutor: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { onPickExecutor() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "switch.2")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.accentSolid)
                                .frame(width: 26)
                            Text("Executor (toggle)").foregroundStyle(Theme.text)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(Theme.surface1)
                }
                Section {
                    ForEach(MacroAction.library) { action in
                        Button { onPick(action) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: action.symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Theme.accentSolid)
                                    .frame(width: 26)
                                Text(action.title).foregroundStyle(Theme.text)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(Theme.surface1)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Assign action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accentSolid)
                }
            }
        }
    }
}

/// Number-pad sheet that points an executor slot at a desk executor (1–9999,
/// current page). Load is disabled until the input is a valid number.
private struct ExecutorLoadSheet: View {
    let onLoad: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var number: Int? {
        guard let n = Int(text), MacroSlot.executorRange.contains(n) else { return nil }
        return n
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextField("Executor number", text: $text)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .font(Theme.mono(size: 24, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .hudPanel()

                Button("Load") { if let n = number { onLoad(n) } }
                    .buttonStyle(AmberCTAStyle())
                    .disabled(number == nil)
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.canvas)
            .navigationTitle("Load Executor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accentSolid)
                }
            }
            .onAppear { focused = true }
        }
    }
}
