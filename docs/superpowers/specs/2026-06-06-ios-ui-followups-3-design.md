# iOS UI Followups — Round 3

**Date:** 2026-06-06
**Branch:** `feat/ios-ui-followups-3` (off `main` @ `62a562e`)
**Scope:** Author-tab restructure — pinned bottom action cluster, Edit mode (multi-delete + drag-reorder), renumbering, a Settings tab, and a bigger mic in the Notes sheet.

## Goal

Make day-to-day cue authoring faster and the chrome cleaner. The Author tab's top bar is stripped to the song menu + an Edit button; the primary actions (Add Cue, Note, Talk) move into one fixed bottom cluster that never scrolls away; cues gain multi-delete, drag-reorder, and renumbering. Settings/Defaults/Pull collapse into a dedicated third tab.

## Two-accent rule (unchanged)

- **Aqua** = capture/voice/notes (Talk button, Note button, Notes sheet mic).
- **Violet `accentGradient`** = the primary brand accent. Reserved for **Send → MA** on the Send tab; reused for **Add Cue** on the Author tab. The two never appear on the same screen (Send is its own tab), so there is no collision.

## Features

### 1. Tab bar: `Author | Send | Settings`

Add a third tab **Settings** (`gear` icon). It absorbs the old top slider-menu entirely. The tab is a `NavigationStack` + `List` with three rows:

- **Pull from MA…** → presents `PullSequencesView` (sheet — it is a network action flow).
- **Defaults…** → presents `DefaultsView`.
- **Settings…** → presents `SettingsView` (host / API keys / connection).

The slider-menu `ToolbarItem` is removed from the Author tab.

### 2. Author top bar — stripped down

- **Principal:** song menu (unchanged — `songMenu`).
- **Trailing:** **Edit** button that toggles Edit mode (see §4). Implemented via `EditButton` bound to the list's `editMode`, or an explicit `@State editMode` toggle.
- The global-Note pencil `ToolbarItem` and the slider-menu `ToolbarItem` are both removed.

### 3. Pinned bottom action cluster (option C)

A fixed `HStack` of three equal big buttons, pinned below the cue list (outside the scroll), replacing the standalone `TalkBarView`-only footer. SF Symbols, no emoji. Each button ~50pt tall, `radiusLarge`.

| Button | Symbol | Color | Action |
|---|---|---|---|
| **Add Cue** | `plus` | violet `accentGradient`, white ink | `store.addCue()` |
| **Note** | `square.and.pencil` | aqua tint fill + aqua border/text | opens global `NotesCaptureView(targetCue: nil)` |
| **Talk** | `mic.fill` | `aquaGradient`, `aquaInk` | existing voice record/stop (current `TalkBarView` behavior) |

- **Add Cue moves out of `CueListView`'s scroll** into this bar — it no longer scrolls with the list.
- The voice button keeps its existing states (recording → `stop.fill` + pulse, busy → spinner, labels via `talkBarLabel`). In the trio it is icon-forward/compact but keeps the same controller wiring.
- **In Edit mode** this trio is replaced by a single destructive **`Delete N cue(s)`** bar (see §4).

### 4. Edit mode

The cue list `CueListView` is converted from `ScrollView { LazyVStack }` to a styled SwiftUI `List`, restyled to match the current look: `.listStyle(.plain)`, `.scrollContentBackground(.hidden)`, `.listRowBackground(Color.clear)`, `.listRowSeparator(.hidden)`, and `.listRowInsets` to reproduce the current spacing. Cue cards render as today in normal mode.

Tapping **Edit** (top trailing) enters edit mode:

- Cues **auto-collapse to compact rows** (number badge + name) for the duration of edit mode, so dragging/selecting tall expanded cards isn't awkward. On exit, prior collapse state is restored (or simply left collapsed — see Open Question O1).
- **Multi-select:** selection circles via `List(selection:)` bound to a `Set<UUID>`.
- **Reorder:** drag handles via `.onMove`, calling `store.moveCues(from:to:)`.
- **Bulk delete:** the bottom trio is swapped for a destructive **`Delete N cue(s)`** button (disabled when selection empty), calling `store.removeCues(ids:)`, then clears selection.
- **Done** (`EditButton` flips to Done) exits; cards return to normal authoring.

### 5. Renumbering

- **Renumber one cue:** tapping a cue's `CueBadge` number opens a small alert with a **decimal `TextField`** (keyboard `.decimalPad`), prefilled with the current number; Save calls `store.setCueNumber(id:to:)`. Supports decimals (`1`, `1.5`, `2.25`). Mirrors the existing rename-song alert pattern. (The badge tap must not conflict with the card's collapse-toggle tap — the badge gets its own tap target.)
- **Enumerate from 1:** a new subbar button (next to collapse/expand-all, symbol `list.number`, accentSolid tint) calling `store.renumberFromOne()` — reassigns `n = 1, 2, 3 …` in current **display (array) order**, integer steps, overwriting any decimals. Pairs with drag-reorder.

### 6. Notes sheet — big mic

In `NotesCaptureView`, replace the small inline "Mic"/"Stop" `Label` button with a **full-width aqua Talk-style button** matching the main screen's `TalkBarView` (aquaGradient pill, `radiusLarge`, mic.fill/stop.fill, pulse while recording, spinner while transcribing). The "Route"/"Add" submit button and routing preview are unchanged. Layout reflows so the big mic is the primary affordance.

## Kit changes (TDD — `ProjectStore+Mutations.swift`)

All operate on the active song. Test first in the Kit suite.

- **`moveCues(from: IndexSet, to: Int)`** — reorders the active song's `cues` array (for `.onMove`).
- **`removeCues(ids: Set<UUID>)`** — bulk-removes cues whose `id` is in the set.
- **`renumberFromOne()`** — sets `cues[k].n = Double(k + 1)` for all k in current array order.
- **`setCueNumber(id: UUID, to n: Double)`** — sets one cue's `n`. (No auto-sort; display order stays array order.)

Existing `addCue`, `removeCue(id:)`, `collapseAllCues`, `expandAllCues`, `applyNotes`, `setNote` are unchanged. `n` remains a display label; the `cues` array order remains the source of truth for display — drag changes order, `renumberFromOne()` syncs labels to order.

## Files touched

- `ios/Sources/App/RootView.swift` — third tab; strip Author top bar to song-menu + Edit; host the pinned bottom cluster + edit-mode delete bar; add `list.number` to subbar; manage `editMode` + `selection` state.
- `ios/Sources/App/CueListView.swift` — `ScrollView`→styled `List` with `selection`/`.onMove`; remove the in-scroll Add Cue button; compact rows in edit mode.
- `ios/Sources/App/CueCardView.swift` — tappable `CueBadge` → renumber-one alert; honor edit-mode compact rendering.
- `ios/Sources/App/SendView.swift` — unchanged (reference for the big-button feel).
- `ios/Sources/App/TalkBarView.swift` — refactor so the voice button is reusable inside the trio (extract the button body, or parameterize).
- `ios/Sources/App/NotesCaptureView.swift` — big aqua mic button.
- **New** `ios/Sources/App/SettingsTabView.swift` — the Settings tab list.
- **New** (optional) a small `BigActionButton` / `BottomActionCluster` component in `Components/` for the trio.
- `ios/Sources/Kit/Store/ProjectStore+Mutations.swift` — the four new methods + tests.

## Out of scope (YAGNI)

- No cross-song cue moves. No cut/copy/paste of cues. No undo. No search/filter. No per-cue color in the renumber flow. Reorder is within the active song only.

## Open questions / small calls (flagged, defaults chosen)

- **O1 — Edit-mode collapse restore:** on exiting edit mode, restore each cue's prior collapsed state, or leave them collapsed? **Default:** restore prior state.
- **O2 — Add Cue insert position:** keep appending to the end (current `addCue` behavior). **Default:** append to end (unchanged); user reorders via drag.
- **O3 — Renumber-one validation:** reject empty/non-numeric; allow duplicates (n is a free label). **Default:** reject non-numeric, allow duplicate numbers.

## Verification

- Kit suite green (4 new methods tested).
- App builds (xcodegen → `iPhone 17 Pro` sim).
- On-device smoke on jPhone (2): add/multi-delete/reorder/renumber cues; pinned cluster works; Settings tab opens all three views; Notes-sheet big mic records.
