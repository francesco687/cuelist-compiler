# Live Tab: Output Lock + 8-Slot Macro Pad — Design

**Date:** 2026-06-12
**Status:** Approved
**Branch:** `feat/live-lock-8-slot-pad` (off `origin/main` `3960f42`)

## Goal

Remove the three fixed transport buttons (GO+/PAUSE/GO−) from the Live tab,
hand that space to a doubled assignable macro pad (2×2 → 2×4), and add an
output lock so a phone in a pocket or handed across the desk can't fire
anything by accident.

GO+/GO−/PAUSE already exist in the `MacroAction` library, so removing the
fixed transport loses no capability — operators assign them to slots.

## Layout (unlocked)

Top to bottom:

1. **Connection row** — unchanged.
2. **Lock bar** — new slim full-width bar: `lock.open.fill` + "TAP TO LOCK"
   in the established HUD style (mono caption, `hudPanel()`).
3. **Macro pad** — 2 columns × 4 rows (8 slots), filling the vertical space
   the transport used to occupy. Cell rendering, picker, load sheet,
   long-press menu, flash press/release, and belief stripe all unchanged.
4. **Message-to-console row** — unchanged.

`TransportButton` is deleted. `PressScaleStyle` stays (macro cells use it).

## Locked state

- **Engage:** single tap on the lock bar. Instant, with haptic.
- **Visual:** everything below the connection row (lock bar, pad, message
  row) dims to ~30% opacity and is hit-disabled (`allowsHitTesting(false)`).
  A centered overlay shows a big `lock.fill` icon with "HOLD TO UNLOCK".
- **Disengage:** press-and-hold ~1 s on the big lock icon with a visible
  progress fill. Releasing early cancels — the lock stays engaged.
- **Connection row stays live** while locked: reconnecting is harmless and
  must not require unlocking.

## Safety semantics

- Engaging the lock calls the existing `flushFlashReleases()` path before
  the surface freezes, so a held FLASH always sends its captured FlashOff —
  the desk is never left flashed behind a lock.
- Lock state is **session-scoped** (`@State` in `LiveView`): an app relaunch
  starts unlocked. This matches the existing belief-state convention
  (`MacroPad.activeExecutors` also resets per launch).
- Scope is the **Live tab surface only**. Other tabs (Program, Send,
  Fixtures, Settings) are untouched; the `HubClient` send path is not gated.

## Slot count migration

`MacroPad.slotCount` goes 4 → 8.

The current UserDefaults loader rejects any saved array whose count ≠
`slotCount`, which would silently wipe every operator's existing 4
assignments on first launch of the new build. Instead, the init:

- accepts a saved `[String]` whose count ≤ `slotCount`, padding it with
  empty-slot markers to the new length (existing assignments land in
  slots 0–3);
- still falls back to all-empty for malformed data (wrong type, or a saved
  array *longer* than `slotCount`);
- persists at the new fixed length of 8 from then on.

## Architecture

- **Lock = view-local state.** `@State private var isLocked` in `LiveView`,
  overlay + hold-gesture rendered in the view. No new model type, no
  persistence. (A `SaettaKit` lock model was considered and rejected: no
  other tab observes the lock, so the machinery buys nothing.)
- **Kit change is migration only.** `MacroPad.swift`: `slotCount = 8` plus
  the padding loader described above.
- **View changes are `LiveView.swift` only** (transport removal, lock bar,
  overlay) — `MacroPadView` already iterates `0..<MacroPad.slotCount` and
  its grid rows grow naturally.

## Testing

- **Kit tests (XCTest, TDD):**
  - legacy 4-element saved array loads into 8 slots with assignments
    preserved in 0–3 and 4–7 empty;
  - persistence round-trips at length 8;
  - malformed / oversized saved data still falls back to all-empty;
  - flash flush on lock relies on the existing `recordFlashFlush` path —
    already covered; the view wires lock-engage to the same call.
- **Manual:** simulator pass (lock/unlock gesture, dimming, hold-cancel),
  then on-device smoke on jPhone (2) + desk acceptance for the flash-flush-
  on-lock behavior.

## Out of scope

- Per-slot locking, lock on other tabs, persisted lock state.
- Picker / load-sheet changes (they already handle arbitrary slot indices).
- Any change to the hub protocol or desk-side behavior.
