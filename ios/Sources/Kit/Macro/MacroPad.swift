import Foundation
import Observation

/// The Live tab's four-slot macro pad. Holds the operator's assigned actions and
/// executor buttons app-wide, persisted to UserDefaults like the hub host/port.
/// Pure state — never touches the network; firing is the view's job via HubClient.
@MainActor
@Observable
public final class MacroPad {
    /// Fixed number of assignable buttons.
    public static let slotCount = 4

    /// One optional action id per slot. `nil` == empty (placeholder) slot.
    public private(set) var slots: [String?]

    /// Believed-active executor targets — the phone's session-scoped belief about
    /// what it set, never desk truth (the transport is one-way; see the
    /// exec-active-indicator design spec for the accepted limitations). Keyed
    /// per-target so every slot pointing at the same target shares one belief.
    /// Deliberately not persisted: belief resets to unknown on every launch.
    public private(set) var activeExecutors: Set<ExecutorTarget> = []

    /// Targets captured at flash press, keyed by slot — mirrors the view's
    /// `flashPressed` release-command capture, so a mid-hold retarget or clear
    /// still releases the belief that was actually engaged.
    @ObservationIgnored private var heldFlash: [Int: ExecutorTarget] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "macroPadSlots"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Stored as a fixed-length [String]; "" marks an empty slot (plist can't hold nil).
        if let saved = defaults.array(forKey: Self.key) as? [String], saved.count == Self.slotCount {
            self.slots = saved.map { $0.isEmpty ? nil : $0 }
        } else {
            self.slots = Array(repeating: nil, count: Self.slotCount)
        }
    }

    /// The decoded value in `slot`, or nil if empty / out of range / undecodable.
    public func slot(at slot: Int) -> MacroSlot? {
        guard slots.indices.contains(slot), let raw = slots[slot] else { return nil }
        return MacroSlot(rawValue: raw)
    }

    /// The action currently in `slot`, or nil if empty / not an action.
    public func action(at slot: Int) -> MacroAction? {
        if case .action(let action)? = self.slot(at: slot) { return action }
        return nil
    }

    /// Make a slot an executor button with no target yet (step 1 of the double
    /// assign), remembering which function it performs. Out-of-range slots are
    /// ignored.
    public func assignExecutor(slot: Int, function: ExecutorFunction) {
        guard slots.indices.contains(slot) else { return }
        slots[slot] = MacroSlot.executor(function: function, target: nil).rawValue
        persist()
    }

    /// Point an executor slot at a target (step 2), keeping the slot's function.
    /// No-op unless the slot currently holds an executor and the target is valid.
    /// Validation mirrors the `MacroSlot` codec exactly (via `MacroSlot.validatedTarget`),
    /// so a stored slot always decodes back: numbers must be in 1...9999; names
    /// are trimmed, and refused if blank, quoted, or containing control characters.
    /// A `.name` whose trimmed content is all ASCII digits is coerced to the
    /// equivalent `.number` — both address the same desk object and the codec
    /// always decodes all-digit targets as numbers.
    public func loadExecutor(slot: Int, target: ExecutorTarget) {
        guard case .executor(let function, _)? = self.slot(at: slot) else { return }
        let validated: ExecutorTarget
        switch target {
        case .number(let n):
            guard MacroSlot.executorRange.contains(n) else { return }
            validated = target
        case .name(let raw):
            guard let v = MacroSlot.validatedTarget(fromRaw: raw) else { return }
            validated = v
        }
        slots[slot] = MacroSlot.executor(function: function, target: validated).rawValue
        persist()
    }

    /// Whether `target` is believed active.
    public func isActive(_ target: ExecutorTarget) -> Bool {
        activeExecutors.contains(target)
    }

    /// Record a successful tap-fire on `slot` — the view calls this only after the
    /// command was actually sent (online + loaded). Toggle flips belief; On latches
    /// it (a toggle slot on the same target can flip it back, matching the desk).
    /// Actions, unloaded executors, flash (press-driven), empty and out-of-range
    /// slots are no-ops.
    public func recordFire(slot: Int) {
        guard case .executor(let function, let target?)? = self.slot(at: slot) else { return }
        switch function {
        case .toggle:
            if activeExecutors.contains(target) { activeExecutors.remove(target) }
            else { activeExecutors.insert(target) }
        case .on:
            activeExecutors.insert(target)
        case .flash:
            break
        }
    }

    /// Record flash touch-down on `slot`: mark its target believed-active and
    /// capture it for the matching release. No-op unless the slot holds a loaded
    /// flash executor (the view gates on the command actually sending).
    public func recordFlashPress(slot: Int) {
        guard case .executor(function: .flash, target: let target?)? = self.slot(at: slot) else { return }
        activeExecutors.insert(target)
        heldFlash[slot] = target
    }

    /// Record flash touch-up/cancel on `slot`: release the belief captured at
    /// press. No-op if this slot has no captured press. Releasing removes the
    /// target from the set even if a toggle/on had latched it — accepted belief
    /// approximation (see spec).
    public func recordFlashRelease(slot: Int) {
        guard let target = heldFlash.removeValue(forKey: slot) else { return }
        activeExecutors.remove(target)
    }

    /// Release every held flash belief — the counterpart of the view's
    /// `flushFlashReleases()` on view disappear / scene backgrounding.
    public func recordFlashFlush() {
        for target in heldFlash.values { activeExecutors.remove(target) }
        heldFlash.removeAll()
    }

    /// Assign an action to a slot. Out-of-range slots are ignored.
    public func assign(slot: Int, action: MacroAction) {
        guard slots.indices.contains(slot) else { return }
        slots[slot] = action.id
        persist()
    }

    /// Empty a slot. Out-of-range slots are ignored.
    public func clear(slot: Int) {
        guard slots.indices.contains(slot) else { return }
        slots[slot] = nil
        persist()
    }

    private func persist() {
        defaults.set(slots.map { $0 ?? "" }, forKey: Self.key)
    }
}
