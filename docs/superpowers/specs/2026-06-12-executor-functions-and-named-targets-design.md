# Executor functions (toggle / flash / on) + named targets — design

**Date:** 2026-06-12
**Status:** Approved
**Builds on:** `2026-06-11-executor-macro-buttons-design.md` (PR #32, merged at `3b37de2`)

## Goal

Extend the Live-tab macro pad's executor buttons in two ways:

1. **Multiple executor functions** — alongside the existing toggle, an executor
   slot can be assigned as **flash** (momentary: lit while held) or **on**
   (one-shot). All three live in the same "Executor" section of the assign
   picker.
2. **Named targets** — an executor slot can target a desk executor by its
   **name string** (as labeled in MA3), not only by number 1–9999.

## Decisions (user-confirmed)

- **Flash is momentary.** Touch-down fires `Flash Executor <t>`, touch-up (or
  gesture cancellation) fires `FlashOff Executor <t>`. The release must fire on
  *every* press end — including when the context-menu long-press interrupts —
  so the desk is never left flashed.
- **MA3 command strings:** `Toggle Executor <t>`, `Flash Executor <t>` /
  `FlashOff Executor <t>`, `On Executor <t>`.
- **Text target = the executor's name on the desk.** It renders quoted in the
  command: `Toggle Executor "Blinders"`. The same function choice applies to
  named targets as to numbered ones. (Raw object paths and free-form commands
  were considered and rejected.)
- **Load sheet uses one smart field.** All-digits input is an executor number;
  anything else non-empty is a name. No mode toggle.
- Numbers stay page-relative (current page), range 1–9999, as in PR #32.

## Approach

Extend the existing string codec over the same UserDefaults `[String]`
storage — no migration, no persistence-layer change. Rejected alternatives:
Codable-JSON-per-slot (migration churn, no user-visible gain) and a generic
custom-command slot (user rejected free commands; named addressing covers the
need with validation intact).

## Kit — `MacroSlot` (ios/Sources/Kit/Macro/MacroSlot.swift)

```swift
public enum MacroSlot: RawRepresentable, Equatable, Sendable {
    case action(MacroAction)
    case executor(function: ExecutorFunction, target: ExecutorTarget?)
}

public enum ExecutorFunction: String, CaseIterable, Sendable {
    case toggle, flash, on
}

public enum ExecutorTarget: Equatable, Sendable {
    case number(Int)      // 1...9999, current page
    case name(String)     // executor label on the desk, non-empty, trimmed
}
```

### Codec

Persisted form: `exec:<function>:<target>`.

- Decode: strip the `exec:` prefix; the **function** is the segment up to the
  next `:`; everything after that colon is the **target verbatim** (so names
  containing `:` survive).
- Empty target → unloaded slot (`target == nil`): renders pending, never fires.
- Target classification: all-digits **and** in 1–9999 → `.number`; anything
  else non-empty → `.name`. (An executor literally named "201" resolves as
  number 201 — addresses the same object on MA3; accepted.)
- All-digits but out of range (e.g. `0`, `10000`) → decode to **nil** (empty
  slot), matching today's fail-safe stance.
- **Legacy compatibility:** `exec:` and `exec:201` (no function segment, i.e.
  the remainder after `exec:` contains no `:` and is empty-or-digits) decode as
  **toggle** with that target. Pads saved by the current build load unchanged.
- Unknown function segment → nil (empty slot). Never a crash, never a bad
  command.
- Encode: always the new three-segment form. (A legacy value re-saves in the
  new form; old builds reading a new value get nil/empty slot, which is the
  same forward-compat behavior as PR #32.)

### Commands

- Target rendering: `.number(201)` → `201`; `.name("Blinders")` →
  `"Blinders"` (double-quoted).
- `command: String?` — what touch-down / tap fires:
  - toggle → `Toggle Executor <t>`
  - flash → `Flash Executor <t>`
  - on → `On Executor <t>`
  - unloaded (`target == nil`) → nil.
- `releaseCommand: String?` — what touch-up fires: `FlashOff Executor <t>` for
  a loaded flash slot, **nil** for everything else.

## Kit — `MacroPad` (ios/Sources/Kit/Macro/MacroPad.swift)

- `assignExecutor(slot:function:)` — step 1 of the double assign, stores an
  unloaded executor with the chosen function.
- `loadExecutor(slot:target:)` — step 2; no-op unless the slot currently holds
  an executor. **Keeps the slot's existing function**, replaces only the
  target. Validates `.number` range; `.name` must be non-empty after trimming.
- `assign`, `clear`, persistence, guard rails unchanged.

## App — picker sheet (MacroPadView.swift)

The "Executor" section gets three rows, each starting the same double-assign
flow with the function baked in:

- Executor (toggle) — `switch.2`
- Executor (flash) — `bolt.fill`
- Executor (on) — `power`

`onPickExecutor` callback grows a `function` parameter.

## App — load sheet

- One text field, `.default` keyboard (was `.numberPad`).
- All-digits input → number, Load enabled only if 1–9999.
- Anything else → name, trimmed; Load enabled if non-empty.
- Title stays "Load Executor"; placeholder becomes "Number or name".

## App — cell rendering + flash gesture

- Loaded cell: target shown big — number in mono as today; names use
  `minimumScaleFactor`/`lineLimit(1)` to fit. Caption shows the **function**:
  `TOGGLE` / `FLASH` / `ON` (replaces the fixed `EXEC` caption).
- Pending cell: `—` over the function caption, dashed border, as today.
- VoiceOver: "Executor 201, flash" / "Executor Blinders, toggle" etc.
- **Flash press handling:** flash cells use a press gesture
  (`DragGesture(minimumDistance: 0)` or equivalent pressed-state reporting):
  - touch-down → send `command`, fire haptic;
  - touch-up **or gesture cancellation** → send `releaseCommand`;
  - release sends only if the press actually sent (no orphan FlashOff), and at
    most once per press.
  - If the context-menu long-press interrupts the press, the release still
    sends.
  - Offline: flash cells dim and don't send, same `canFire` rule as today.
- Toggle/On cells keep the plain tap → `command` path. Context menu (Load
  Executor… / Reassign… / Clear), offline dimming, pending-tap-opens-load-sheet
  all unchanged.

## Testing

Kit (XCTest, in `ios/Tests/`):

- Codec round-trip: every function × number/name/unloaded; legacy `exec:` and
  `exec:201` decode as toggle; re-encode of legacy is three-segment.
- Malformed decodes to nil: unknown function, out-of-range digits, empty
  string after trim.
- Edge targets: name containing `:`; all-digit name boundary (`"201"` →
  number; `"0"`/`"10000"` → nil).
- `command` / `releaseCommand` per function and per target kind;
  `releaseCommand` nil for toggle/on/unloaded.
- `MacroPad`: assign with each function; load preserves function; name
  validation; legacy slot loads.

Flash gesture press/release ordering is covered at the slot level (command
strings); the gesture itself is verified on device during desk acceptance.

## Out of scope

- Page-qualified numbers (`2.201`) — still current page only.
- Desk-side name validation/autocomplete — the name is sent as typed.
- Momentary behavior for On (it's one-shot by decision).
