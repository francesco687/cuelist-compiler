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
    /// No-op unless the slot currently holds an executor and the target is valid:
    /// numbers must be in range; names non-blank (stored trimmed), with quotes
    /// and control characters refused — mirroring what the MacroSlot codec will
    /// accept back, so a stored slot always decodes.
    public func loadExecutor(slot: Int, target: ExecutorTarget) {
        guard case .executor(let function, _)? = self.slot(at: slot) else { return }
        let validated: ExecutorTarget
        switch target {
        case .number(let n):
            guard MacroSlot.executorRange.contains(n) else { return }
            validated = target
        case .name(let raw):
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  !name.contains("\""),
                  !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else { return }
            validated = .name(name)
        }
        slots[slot] = MacroSlot.executor(function: function, target: validated).rawValue
        persist()
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
