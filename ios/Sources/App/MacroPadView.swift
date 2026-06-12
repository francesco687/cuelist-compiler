import SwiftUI
import SaettaKit

/// The Live tab's 2×2 macro pad. Each cell holds an assignable value that fires on
/// the desk through the hub's `cmd` passthrough: a parameter-free action (runs on
/// the desk-selected executor) or an executor button — toggle / on fire on tap,
/// flash is momentary (Flash on touch-down, FlashOff on touch-up or cancel) —
/// targeting an executor by number (current page) or by desk name. Tap empty →
/// picker; tap assigned → fire; tap an unloaded executor → load sheet; long-press
/// assigned → load/reassign/clear.
struct MacroPadView: View {
    @Environment(MacroPad.self) private var pad
    @Environment(HubClient.self) private var hub
    @Environment(\.scenePhase) private var scenePhase
    let onFire: () -> Void                     // haptic trigger, shared with transport

    private struct SlotTarget: Identifiable { let id: Int }   // id == slot index
    @State private var picker: SlotTarget?
    @State private var execLoad: SlotTarget?
    /// Slot → releaseCommand captured at touch-down. Populated only when the Flash
    /// command was actually sent, so the matching FlashOff is gated (at most once per
    /// press, never orphaned). The command string is captured at press time, not
    /// re-read at release, so FlashOff always targets the executor the Flash was sent
    /// to even if the slot is cleared or retargeted mid-press. The dictionary is
    /// flushed on view disappear and on scene backgrounding so the desk is never left
    /// in a flashed state by a navigation or app-lifecycle transition (transport loss
    /// is a known limitation surfaced at desk acceptance).
    @State private var flashPressed: [Int: String] = [:]

    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<MacroPad.slotCount, id: \.self) { slot in
                MacroButton(
                    slot: pad.slot(at: slot),
                    isOnline: hub.state.isOnline,
                    isActive: believedActive(slot),
                    onTap: { handleTap(slot) },
                    onFlashPress: { handleFlashPress(slot) },
                    onFlashRelease: { handleFlashRelease(slot) },
                    onLoadExecutor: { execLoad = SlotTarget(id: slot) },
                    onReassign: { picker = SlotTarget(id: slot) },
                    onClear: { pad.clear(slot: slot) }
                )
            }
        }
        .onDisappear { flushFlashReleases() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flushFlashReleases() }
        }
        .sheet(item: $picker) { target in
            MacroPickerSheet(
                onPick: { action in
                    pad.assign(slot: target.id, action: action)
                    picker = nil
                },
                onPickExecutor: { function in
                    pad.assignExecutor(slot: target.id, function: function)
                    picker = nil
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $execLoad) { target in
            ExecutorLoadSheet(onLoad: { execTarget in
                pad.loadExecutor(slot: target.id, target: execTarget)
                execLoad = nil
            })
            .presentationDetents([.height(240)])
        }
    }

    private func handleTap(_ slot: Int) {
        switch pad.slot(at: slot) {
        case nil:
            picker = SlotTarget(id: slot)              // empty slot — assign even offline
        case .executor(_, nil):
            execLoad = SlotTarget(id: slot)            // step 2 of the double assign
        case let value?:
            guard hub.state.isOnline, let command = value.command else { return }
            hub.sendCommand(command)
            pad.recordFire(slot: slot)
            onFire()
        }
    }

    /// Touch-down on a loaded flash cell: engage flash and capture the release
    /// command now so FlashOff always targets the same executor even if the slot
    /// is cleared or retargeted before touch-up.
    private func handleFlashPress(_ slot: Int) {
        guard hub.state.isOnline,
              let command = pad.slot(at: slot)?.command,
              let release = pad.slot(at: slot)?.releaseCommand else { return }
        hub.sendCommand(command)
        flashPressed[slot] = release
        pad.recordFlashPress(slot: slot)
        onFire()
    }

    /// Touch-up or gesture cancel on a flash cell: send the release command that
    /// was captured at press time — only if this press actually engaged the flash.
    private func handleFlashRelease(_ slot: Int) {
        guard let release = flashPressed.removeValue(forKey: slot) else { return }
        hub.sendCommand(release)
        pad.recordFlashRelease(slot: slot)
    }

    /// Send FlashOff for every currently-held flash and clear the dictionary.
    /// Called on view disappear and scene backgrounding so the desk is never left
    /// in a flashed state by a navigation or lifecycle transition.
    private func flushFlashReleases() {
        for release in flashPressed.values { hub.sendCommand(release) }
        flashPressed.removeAll()
        pad.recordFlashFlush()
    }

    /// Belief for the stripe: only loaded executor slots have one.
    private func believedActive(_ slot: Int) -> Bool {
        guard case .executor(_, let target?)? = pad.slot(at: slot) else { return false }
        return pad.isActive(target)
    }
}

/// One macro-pad cell, rendered per slot value:
/// action → tinted symbol + title; loaded executor → big target over its function
/// caption (TOGGLE / FLASH / ON); unloaded executor → pending "—"; empty →
/// dashed Assign placeholder.
private struct MacroButton: View {
    let slot: MacroSlot?
    let isOnline: Bool
    let isActive: Bool
    let onTap: () -> Void
    let onFlashPress: () -> Void
    let onFlashRelease: () -> Void
    let onLoadExecutor: () -> Void
    let onReassign: () -> Void
    let onClear: () -> Void

    private var isExecutor: Bool {
        if case .executor = slot { return true }
        return false
    }

    /// Loaded flash cells fire on press/release, not tap.
    private var isMomentary: Bool {
        if case .executor(function: .flash, target: .some) = slot { return true }
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

    @ViewBuilder private var button: some View {
        if isMomentary {
            // Momentary flash: the Button supplies pressed state; the style relays
            // touch-down/up — SwiftUI clears isPressed on cancellation too (e.g.
            // the context-menu long-press taking over). View-level flush covers
            // teardown/backgrounding; transport loss is a known limitation surfaced
            // at desk acceptance.
            Button(action: {}) {
                content
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
            }
            .buttonStyle(PressReportingScaleStyle(onPress: onFlashPress, onRelease: onFlashRelease))
            .accessibilityAction {
                onFlashPress()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    onFlashRelease()
                }
            }
            .opacity(canFire && !isOnline ? 0.4 : 1)
        } else {
            Button(action: onTap) {
                content
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
            }
            .buttonStyle(PressScaleStyle())
            .opacity(canFire && !isOnline ? 0.4 : 1)
        }
    }

    @ViewBuilder private var content: some View {
        switch slot {
        case .action(let action):
            VStack(spacing: 6) {
                Image(systemName: action.symbol).font(.system(size: 26, weight: .bold))
                    .accessibilityHidden(true)
                Text(action.title).font(.system(size: 17, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.accentSolid.gradient, in: RoundedRectangle(cornerRadius: Theme.radius))
            .accessibilityLabel("\(action.title), macro")
        case .executor(let function, let target?):
            VStack(spacing: 2) {
                targetText(target)
                Text(function.caption).font(.system(size: 11, weight: .semibold)).opacity(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.accentSolid.gradient, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(alignment: .leading) {
                // Belief stripe: what Saetta thinks it set, not desk truth.
                Capsule()
                    .fill(isActive ? Theme.execActive : Theme.execInactive)
                    .frame(width: 4)
                    .padding(.vertical, 10)
                    .padding(.leading, 6)
                    .animation(.easeInOut(duration: 0.15), value: isActive)
            }
            .accessibilityLabel("Executor \(target.display), \(function.rawValue), \(isActive ? "active" : "inactive")")
        case .executor(let function, nil):
            VStack(spacing: 2) {
                Text("\u{2014}").font(Theme.mono(size: 26, weight: .heavy))
                Text(function.caption).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            )
            .accessibilityLabel("Executor pending, tap to load")
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

    /// Numbers keep the big mono treatment; names shrink to fit one line.
    @ViewBuilder private func targetText(_ target: ExecutorTarget) -> some View {
        switch target {
        case .number(let n):
            Text("\(n)").font(Theme.mono(size: 26, weight: .heavy))
        case .name(let name):
            Text(name)
                .font(.system(size: 17, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 6)
        }
    }
}

/// PressScaleStyle that also reports touch-down / touch-up, for momentary cells.
struct PressReportingScaleStyle: ButtonStyle {
    let onPress: () -> Void
    let onRelease: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                pressed ? onPress() : onRelease()
            }
    }
}

/// Lists the three executor functions then the curated macro library; one tap
/// assigns and dismisses.
private struct MacroPickerSheet: View {
    let onPick: (MacroAction) -> Void
    let onPickExecutor: (ExecutorFunction) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let executorRows: [(function: ExecutorFunction, title: String, symbol: String)] = [
        (.toggle, "Executor (toggle)", "switch.2"),
        (.flash, "Executor (flash)", "bolt.fill"),
        (.on, "Executor (on)", "power"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Executor") {
                    ForEach(Self.executorRows, id: \.function) { row in
                        Button { onPickExecutor(row.function) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: row.symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Theme.accentSolid)
                                    .frame(width: 26)
                                Text(row.title).foregroundStyle(Theme.text)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(Theme.surface1)
                    }
                }
                Section("Actions") {
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
            .navigationTitle("Assign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accentSolid)
                }
            }
        }
    }
}

/// One smart field that points an executor slot at a desk executor: all-digits
/// input is a number (1–9999, current page), anything else is the executor's
/// desk name. Validation is `MacroSlot.validatedTarget` — the same rule the pad
/// applies on store — so Load can never accept what the pad would refuse.
private struct ExecutorLoadSheet: View {
    let onLoad: (ExecutorTarget) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var target: ExecutorTarget? {
        MacroSlot.validatedTarget(fromRaw: text)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextField("Number or name", text: $text)
                    .keyboardType(.default)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                    .font(Theme.mono(size: 24, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .hudPanel()

                Button("Load") { if let t = target { onLoad(t) } }
                    .buttonStyle(AmberCTAStyle())
                    .disabled(target == nil)
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
