# Executor toggle buttons on the Live macro pad — design

**Date:** 2026-06-11
**Status:** Approved
**Scope:** iOS app (`ios/`), Live tab macro pad. No hub, web, or desktop changes.

## Goal

Let the operator put an **executor toggle** on any of the four assignable macro-pad
slots on the Live tab. The interaction is a deliberate **double assign**:

1. **Assign** — from the existing assign picker, choose the new "Executor (toggle)"
   entry. The slot becomes an executor button with no target yet.
2. **Load** — long-press the button and choose **"Load Executor…"** to enter the
   executor number (e.g. `201`). The button is now armed.

After both steps, a normal tap fires `Toggle Executor <n>` at the desk through the
hub's existing `cmd` passthrough — the same channel the transport buttons, console
message, and existing macro actions use. The number targets the desk's **current
page** (same semantics as pressing the physical executor key).

## Interaction details

| State | Render | Tap | Long-press (context menu) |
|---|---|---|---|
| Empty slot | dashed "Assign" placeholder (unchanged) | open assign picker (unchanged) | — (unchanged) |
| Action slot (existing) | tinted symbol + title (unchanged) | fire command (unchanged) | Reassign… / Clear (unchanged) |
| Executor slot, **unloaded** | pending style: `EXEC —` | open the load sheet (never fires; no malformed command possible) | **Load Executor…** / Reassign… / Clear |
| Executor slot, **loaded** | number big (`201`) over `EXEC` caption | fire `Toggle Executor 201` + haptic; disabled/dimmed when hub offline (same rule as action slots) | **Load Executor…** (re-target) / Reassign… / Clear |

- The load sheet is a small sheet with a number-pad text field, validating an
  integer in **1…9999**. Confirm is disabled for invalid input. Cancel leaves the
  slot unchanged.
- Loading a new number over an already-loaded slot simply re-targets it.
- "Reassign…" returns the slot to the assign picker flow (can become an action or a
  fresh unloaded executor). "Clear" empties the slot. Both unchanged in behavior.
- Assignment and loading work offline (consistent with today's "assign even
  offline" rule); only **firing** requires the hub online.

## Implementation shape

### Kit (`ios/Sources/Kit/Macro/`)

**New `MacroSlot.swift`** — the slot value type:

```swift
public enum MacroSlot: Equatable, Sendable {
    case action(MacroAction)
    case executor(number: Int?)        // nil == assigned but not loaded
}
```

- `var command: String?` — `nil` for `.executor(nil)`; `"Toggle Executor <n>"` for
  a loaded executor; the action's command otherwise. Built in Kit so it is
  unit-testable.
- String (de)serialization for the existing `UserDefaults` `[String]` storage:
  - plain library id (e.g. `"go_plus"`) → `.action` (legacy values load unchanged,
    **no migration needed**)
  - `"exec:"` → `.executor(number: nil)`
  - `"exec:201"` → `.executor(number: 201)`
  - unknown/garbage → `nil` (empty slot), matching today's unknown-id behavior
- Executor number range constant `1...9999`, used by both decoding and the sheet's
  validation.

**`MacroPad` changes** — slots become `[MacroSlot?]` semantically (storage format
unchanged):

- `slot(at:) -> MacroSlot?` replaces `action(at:)` as the primary accessor.
- `assign(slot:action:)` — unchanged behavior (wraps in `.action`).
- `assignExecutor(slot:)` — sets `.executor(number: nil)`.
- `loadExecutor(slot:number:)` — sets `.executor(number: n)`; rejects out-of-range
  numbers (no-op), only applies to slots currently holding an executor.
- `clear(slot:)` — unchanged.
- Persistence stays a fixed-length `[String]` under the existing `"macroPadSlots"`
  key; `""` still marks empty.

### App (`ios/Sources/App/`)

**`MacroPadView.swift`**:

- `MacroButton` renders the two executor states per the table above (pending
  `EXEC —` uses the placeholder palette; loaded shows the number in the heavy mono
  style with an `EXEC` caption, same tinted-fill treatment as action buttons).
- Context menu for executor slots adds **"Load Executor…"** above
  Reassign…/Clear.
- Tap routing: unloaded executor → load sheet; loaded executor → send
  `slot.command` + `onFire()` haptic, gated on `hub.state.isOnline` exactly like
  action slots.
- New private `ExecutorLoadSheet`: number-pad field, 1–9999 validation, Confirm /
  Cancel; presented via a sheet item carrying the slot index (same `SlotTarget`
  pattern as the picker).
- `MacroPickerSheet` gains an "Executor (toggle)" row (distinct glyph, e.g.
  `switch.2`) in its own section **above** the action library list; picking it
  calls `assignExecutor` and dismisses.

## Error handling

- No target → no command: `.executor(nil)` has `command == nil` and the tap path
  opens the sheet instead, so a malformed `Toggle Executor` can never reach the
  desk.
- Invalid persisted strings (`"exec:abc"`, `"exec:0"`, `"exec:99999"`) decode to
  `nil` → empty slot, never a crash or bad command.
- Hub offline: identical to existing behavior — assigned buttons dim and don't
  fire; assignment/loading still allowed.

## Testing (Kit, XCTest — extend existing macro tests)

1. `MacroSlot` string round-trip: library id, `"exec:"`, `"exec:201"`; garbage and
   out-of-range strings decode to `nil`.
2. `command`: loaded executor → `"Toggle Executor 201"`; unloaded → `nil`;
   action passthrough unchanged.
3. `MacroPad.assignExecutor` / `loadExecutor`: happy path, out-of-range number
   rejected, `loadExecutor` on a non-executor slot rejected, persistence
   round-trip through a fresh `MacroPad` on the same `UserDefaults` suite.
4. Legacy compatibility: a saved `["go_plus", "", "", ""]` array loads as today.

UI states verified by build + on-device/sim eyeball (matches how the existing pad
shipped).

## Out of scope (YAGNI)

- Page-pinned targets (`2.201`) — current-page only, per decision.
- Other executor verbs (Flash, Temp, Go on a specific exec) — the slot model
  makes them easy to add later as new cases/commands.
- Live executor state feedback (button reflecting on/off at the desk) — the cmd
  channel is fire-and-forget today.
- Web/desktop parity.
