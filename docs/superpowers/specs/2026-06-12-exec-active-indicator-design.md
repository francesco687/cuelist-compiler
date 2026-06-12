# Executor Active Indicator (Live tab) — Design

**Date:** 2026-06-12
**Status:** Approved by user (phone-side belief model confirmed)
**Scope:** iOS only (`ios/Sources/Kit` + `ios/Sources/App`). No hub, relay, or protocol changes.

## Problem

The Live tab's macro pad fires executor commands (toggle / flash / on) at the desk, but
gives the operator no feedback about whether an executor is currently active. The
operator wants an at-a-glance indicator on every executor cell: **red** when inactive,
**green** when active.

## Truth model (decided)

The indicator shows **phone-side belief** — what Saetta itself believes it set — not desk
truth. The transport is one-way (phone → hub → OSC → desk); no executor state ever comes
back. Accepted limitations, all session-scoped:

- Changes made at the desk itself (or by another operator) are invisible to the indicator.
- On app launch everything starts red (unknown), regardless of desk state.
- A hub/transport drop mid-flash-hold shows red even though the desk may still be flashed
  (same documented limitation as the FlashOff flush).
- A numbered and a named reference to the same physical executor cannot be correlated —
  they track belief independently.

A future slice may upgrade the same indicator to real desk feedback (MA3 OSC echo spike
required); the UI layer is designed to be source-agnostic so nothing here is throwaway.

## State model

Belief lives in `MacroPad` (Kit) — observable, app-wide, testable. **Not persisted**:
belief resets on every app launch; it survives hub reconnects (it is no staler after a
drop than before, and offline dimming already signals "can't fire").

- `ExecutorTarget` gains `Hashable` conformance.
- `MacroPad` gains:
  - `public private(set) var activeExecutors: Set<ExecutorTarget>` — believed-active
    targets. Keyed **per-target, not per-slot**: two slots pointing at the same target
    (e.g. `toggle:201` and `flash:201`) share one belief. Key collisions are impossible:
    all-digit names are already coerced to `.number` by `loadExecutor` and the codec, so
    `.name` and `.number` never alias.
  - `private var heldFlash: [Int: ExecutorTarget]` — targets captured at flash press,
    keyed by slot, mirroring the view's `flashPressed` release-command capture so a
    mid-hold retarget/clear still releases the belief that was engaged.
- Transition API (called by the view only after a successful send — online + non-nil
  command; pure state, `MacroPad` still never touches the network):
  - `recordFire(slot: Int)` — tap on a loaded executor slot. `toggle` → toggle set
    membership; `on` → insert. Action slots, empty slots, and unloaded executors no-op.
  - `recordFlashPress(slot: Int)` — insert target into `activeExecutors`, capture it in
    `heldFlash[slot]`.
  - `recordFlashRelease(slot: Int)` — remove the captured target from both, no-op if the
    slot has no captured press (mirrors the view's guard).

Flash release removes the target from the active set even if a prior toggle/on had
latched it — an accepted belief approximation (the desk's FlashOff behavior on a running
sequence is itself state-dependent; belief stays simple).

`clear(slot:)` / reassign leave `activeExecutors` untouched: belief is per-target and
other slots may still reference it. Stale entries are harmless and session-scoped.

## Semantics recap

| Function | On successful send | Indicator |
| --- | --- | --- |
| Toggle | tap | flips belief (default red → green) |
| On | tap | latches green; a toggle slot on the same target can flip it back (matches desk) |
| Flash | press / release (incl. `flushFlashReleases()` on disappear/background) | green while held, red on release/flush |

## View wiring (`MacroPadView`)

- `handleTap` success path additionally calls `pad.recordFire(slot:)`.
- `handleFlashPress` success path additionally calls `pad.recordFlashPress(slot:)`.
- `handleFlashRelease` calls `pad.recordFlashRelease(slot:)` alongside sending the
  captured release command; `flushFlashReleases()` does the same per held slot.

## UI

On every **loaded executor** cell (not action cells, not pending/unloaded executors, not
empty slots):

- A vertical stripe on the **left edge**: ~4pt wide, rounded ends, inset from top/bottom,
  layered inside the cell's rounded rect so it never breaks the cell silhouette.
- Red when believed inactive, green when believed active. New theme constants (the amber
  HUD has no green; the user explicitly chose red/green for this affordance):
  - `Theme.execInactive` = `#ff6b6b` (same hue as `danger`, scoped name so "inactive" is
    not semantically "destructive")
  - `Theme.execActive` = `#4cd964` (iOS-classic green, reads instantly against amber)
- Color change animates briefly (`.easeInOut`, ~0.15s); flash press reads as immediate.
- The stripe dims with the rest of the cell when offline (it sits inside the existing
  `.opacity` modifier).
- Accessibility: the cell's `accessibilityLabel` gains a trailing `, active` /
  `, inactive` for loaded executor cells.

## Testing

Kit tests (extend `ios/Tests/KitTests/MacroPadTests.swift`) for the transition table:

- toggle tap flips belief on/off; on tap latches; repeated on stays active.
- flash press inserts + release removes; release without press no-ops; mid-hold retarget
  still releases the originally captured target.
- shared target across two slots: one belief entry drives both.
- toggle on a target latched by `on` flips it red (cross-function interplay).
- action slots / unloaded executors / empty / out-of-range slots never touch the set.
- name vs number independence: `.name("201x")`-style names and `.number(201)` don't alias;
  all-digit name coercion means keys can't collide.
- `clear(slot:)` leaves belief untouched.
- belief is not persisted: a fresh `MacroPad` from the same `UserDefaults` starts empty.

UI verified on device (manual): stripe states across all three functions, offline
dimming, VoiceOver labels.

## Out of scope

- Desk-truth feedback (OSC echo) — future slice, needs hardware spike.
- Any hub / relay / protocol change.
- Persisting belief across launches.
