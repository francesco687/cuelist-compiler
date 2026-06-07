# Macro Pad — assignable action buttons on the Live tab

**Date:** 2026-06-07
**Status:** Approved (brainstorm) → ready for implementation plan

## Goal

Add four big assignable buttons to the Live tab. Each holds a "selectable macro" — a
parameter-free grandMA3 command that fires on the desk-selected executor. Tap an empty
button to pick a macro from a curated list; tap an assigned button to fire it; long-press
to reassign or clear. Assignments are app-wide and persistent.

This is purely additive: it reuses the existing `cmd` passthrough already used by the
transport buttons and the console-message feature. **No hub or protocol change.**

## Decisions (locked during brainstorm)

| Question | Decision |
|---|---|
| Action source | Curated library only (no free-typed commands) |
| Action scope | Parameter-free, acts on the desk-selected executor (like GO+/PAUSE/GO−) |
| Library v1 | `Go+`, `Go-`, `Pause`, `Off`, `On`, `Top` (Flash dropped — it's press-and-hold, not one-tap) |
| Library growth | Append-only list; adding a macro later is a one-line change |
| Layout | **A — Stacked:** connection row → transport → 2×2 macro pad → message field |
| Assign | Tap empty button → picker sheet → one tap assigns and dismisses |
| Fire | Tap assigned button → fires via `hub.sendCommand`, optimistic, same haptic as transport |
| Edit/clear | Long-press assigned button → context menu: *Reassign…* / *Clear* |
| Empty state | Darker surface + dashed border + "+" placeholder |
| Persistence | Global (app-wide), `UserDefaults`-backed like the hub host/port |
| Slot count | Fixed at 4 |

## Layout

Live tab, top to bottom:

1. Connection row (unchanged)
2. GO+ / PAUSE / GO− transport (unchanged)
3. **2×2 macro pad (new)** — between transport and the message field
4. Message-to-console field (unchanged)

The pad is sized to fit without scrolling on common phones; the screen scrolls gracefully
if a small phone runs short on vertical space.

## Button states

- **Assigned:** tinted fill, SF Symbol + short title (e.g. "OFF"). Tap fires the command
  optimistically through the existing `hub.sendCommand`, with the same medium-impact haptic
  and press-pulse as the transport buttons. Dimmed/disabled when the hub is offline (matches
  transport).
- **Empty:** darker surface + dashed border + a "+" placeholder. Tap opens the picker.
  Never disabled by offline state — assigning is a local operation.

## Interactions

- Tap **empty** button → picker sheet lists the library → one tap assigns and dismisses.
- Tap **assigned** button → fires the macro's command.
- Long-press **assigned** button → context menu: *Reassign…* (reopens the picker) /
  *Clear* (empties the slot).

## Components

### Kit (pure, testable)

- **`MacroAction`** — value type: `id`, `title`, `symbol`, `command` (the literal
  command-line string, e.g. `"Go+"`). Static `MacroAction.library: [MacroAction]` holds the
  v1 six. Growing the library = append an entry.
- **`MacroPad`** — `@MainActor @Observable` store owning `slots: [MacroAction.ID?]` (fixed
  count 4), backed by `UserDefaults` like the hub host/port. API: `assign(slot:action:)`,
  `clear(slot:)`, `action(at:)`. Isolated from connection concerns. Injected via the
  environment like `HubClient`.

### App (SwiftUI)

- **`MacroPadView`** — the 2×2 grid; reads `MacroPad`, fires through `HubClient`.
- **`MacroButton`** — one cell; renders assigned/empty state, handles tap + long-press
  context menu.
- **`MacroPickerSheet`** — renders `MacroAction.library` as a tap-to-assign list.

### Wiring

- `MacroPadView` dropped into `LiveView` between the transport stack and `controlSection`.
- `MacroPad` created in `App.swift` alongside `HubClient` and placed in the environment.

## Data flow

- **Fire:** tap → `MacroPad.action(at: slot)` → `hub.sendCommand(action.command)`.
- **Assign:** picker tap → `MacroPad.assign(slot:action:)` → persists to `UserDefaults` →
  `@Observable` refreshes the grid.

Rides the same `cmd` passthrough as transport and console-message. Zero hub/protocol change.

## Error handling

Optimistic, no ack — identical to the transport buttons. Offline → assigned pad buttons
dim/disable; `sendCommand` already auto-connects and no-ops when there's no socket.
Assign/clear never touch the network.

## Testing (Kit-level, matching house style)

- **`MacroAction.library`:** ids unique; titles/symbols/commands non-empty; exact command
  strings (`Go+`, `Go-`, `Pause`, `Off`, `On`, `Top`).
- **`MacroPad`:** assign sets the slot; clear nils it; reassign replaces; out-of-range slot
  is a safe no-op; fixed 4 slots; a `UserDefaults` round-trip survives re-init.
- UI (grid / picker / long-press) is not unit-tested — same call made for the transport
  buttons (offline-path HubClient test was likewise skipped).

## Open / deferred (non-blocking)

- Exact MA3 command strings verified against the real desk during the on-desk smoke test
  (house style here).
- Library growth is a one-line append per macro.
- Duplicates allowed — the same macro on two buttons is fine.
