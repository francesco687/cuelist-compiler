import Foundation
import Observation

/// The Live tab's four-slot macro pad. Holds the operator's assigned actions app-wide,
/// persisted to UserDefaults like the hub host/port. Pure state — never touches the
/// network; firing is the view's job via HubClient.
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

    /// The action currently in `slot`, or nil if empty / out of range / unknown id.
    public func action(at slot: Int) -> MacroAction? {
        guard slots.indices.contains(slot), let id = slots[slot] else { return nil }
        return MacroAction.find(id)
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
