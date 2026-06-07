import SwiftUI
import SaettaKit

/// The Live tab's 2×2 macro pad. Each cell holds an assignable parameter-free action
/// that fires on the desk-selected executor through the hub's `cmd` passthrough.
/// Tap empty → picker; tap assigned → fire; long-press assigned → reassign/clear.
struct MacroPadView: View {
    @Environment(MacroPad.self) private var pad
    @Environment(HubClient.self) private var hub
    let onFire: () -> Void                     // haptic trigger, shared with transport

    private struct SlotTarget: Identifiable { let id: Int }   // id == slot index
    @State private var picker: SlotTarget?

    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<MacroPad.slotCount, id: \.self) { slot in
                MacroButton(
                    action: pad.action(at: slot),
                    isOnline: hub.state.isOnline,
                    onTap: { handleTap(slot) },
                    onReassign: { picker = SlotTarget(id: slot) },
                    onClear: { pad.clear(slot: slot) }
                )
            }
        }
        .sheet(item: $picker) { target in
            MacroPickerSheet(onPick: { action in
                pad.assign(slot: target.id, action: action)
                picker = nil
            })
            .presentationDetents([.medium, .large])
        }
    }

    private func handleTap(_ slot: Int) {
        if let action = pad.action(at: slot) {
            guard hub.state.isOnline else { return }   // assigned buttons need the hub
            hub.sendCommand(action.command)
            onFire()
        } else {
            picker = SlotTarget(id: slot)              // empty slot — assign even offline
        }
    }
}

/// One macro-pad cell. Assigned: tinted fill + symbol + title, fires on tap, long-press
/// menu to reassign/clear. Empty: darker dashed placeholder, tap opens the picker.
private struct MacroButton: View {
    let action: MacroAction?
    let isOnline: Bool
    let onTap: () -> Void
    let onReassign: () -> Void
    let onClear: () -> Void

    var body: some View {
        if action != nil {
            button.contextMenu {
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
        .opacity(action != nil && !isOnline ? 0.4 : 1)   // dim assigned buttons when offline
    }

    @ViewBuilder private var content: some View {
        if let action {
            VStack(spacing: 6) {
                Image(systemName: action.symbol).font(.system(size: 26, weight: .bold))
                Text(action.title).font(.system(size: 17, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.accentSolid.gradient, in: RoundedRectangle(cornerRadius: Theme.radius))
        } else {
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

/// Lists the curated macro library; one tap assigns and dismisses.
private struct MacroPickerSheet: View {
    let onPick: (MacroAction) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(MacroAction.library) { action in
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
