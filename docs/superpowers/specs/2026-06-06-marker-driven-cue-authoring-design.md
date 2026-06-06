# Marker-driven cue authoring — design

**Date**: 2026-06-06
**Status**: Spec (pending implementation plan)
**Component**: `web/` (compiler authoring UI)

## Problem

Authoring TC-per-cue today requires typing timecodes by hand into each cue's `position` field. With a long song this is slow and disconnected from the music. The recently-shipped TC-per-cue feature (PR #9 + #10) makes per-cue TC the natural authoring unit — we need a musical way to capture those TCs.

## Goal

Drop a marker on the audio waveform while listening; a cue is created underneath with `position` set to that moment. Drop them out of order; the list reorders itself.

## User flow

1. **Load track** (no change — existing `Load Audio…` button).
2. **Press `M`** at any time (playback running or paused) → a marker is dropped at the current playhead position. A new cue appears in the cue list with `position` filled.
3. **Adjust timing** by dragging a marker pin on the waveform with the mouse; the cue's `position` updates live.
4. **Remove a marker** by clicking the pin to select it (highlight), then pressing `Delete` or `Backspace`. The cue is removed.
5. After every append, drag-end, or delete: cues are **re-sorted by ascending TC** and **renumbered `n = 1..N`** in TC order.

## Design decisions (locked)

| # | Decision | Why |
|---|---|---|
| 1 | Hotkey `M` is the only drop trigger. | Hands stay on keyboard, eyes on waveform — musical workflow. Click-to-drop on waveform is reserved for scrubbing (existing behavior). |
| 2 | `M` always live when a song with audio is active. No explicit "record mode" toggle. | YAGNI — risk of accidental drops is low (`M` requires no modifier, but is also outside any text-input context — see edge cases). |
| 3 | New cue is auto-populated with `position` only; `n` = next available, `name = ''`, `actions = []`. | Marker authoring is a *timing* operation; content authoring is done after, in the existing cue UI. |
| 4 | After mutation: sort by `timecodeToSeconds(position)` ascending, renumber `n = 1..N`. | Keeps MA3 cue numbers aligned with chronological order, which is the desk convention. Renumbering is harmless because cues created via marker drop are otherwise empty. |
| 5 | Mouse drag on the waveform corrects timing. No snap-to-transient. | Drag is the natural visual correction; transient detection is out of scope for this iteration. |
| 6 | Delete: click pin → selected (highlighted) → `Delete`/`Backspace` removes. | Explicit two-step prevents accidental loss; selection also enables future fine-tune-by-arrows. |

## Components touched (`web/js/`)

| File | Change |
|---|---|
| `audio.js` | New: `dropMarkerAtPlayhead()`, `startMarkerDrag(cueN, evt)`, `selectMarker(cueN)`, `deselectAllMarkers()`. Modify: `renderMarkers()` adds a `.selected` class hook, attaches `mousedown` drag handler, attaches selection handler. |
| `state.js` | New: `appendCueWithTcAndResort(songId, tc)`. Creates the cue (next `n`, empty fields), pushes, sorts cues by `timecodeToSeconds(position)`, renumbers `n = 1..N`, calls `saveState()`. Also exposed: `resortAndRenumber(songId)` used by drag-end and delete paths. |
| `main.js` | Global `keydown` listener: `M` → `dropMarkerAtPlayhead()`; `Delete`/`Backspace` with a selected marker → remove cue + `resortAndRenumber`. Both handlers no-op if focus is in `input`, `textarea`, or `[contenteditable]` so typing in cue names is unaffected. |
| `render.js` | No structural change. The cue list already renders from `state` in array order; the re-sort + renumber in `state.js` flows through naturally on the next `render()` call after each mutation. |
| `css/` (existing stylesheet) | `.marker.selected` highlight (e.g. accent-color outline). `.marker` gets `cursor: grab`; during drag `cursor: grabbing`. |

## Data model

No schema change. The cue object stays:

```js
{ n, position, name, actions, collapsed }
```

`position` is a TC string in the existing format (whatever `secondsToTimecode` emits — already used by `captureCurrentPlayheadAsSmpte`).

## Edge cases

| Case | Behavior |
|---|---|
| `M` pressed while focus is in a text input / textarea / contenteditable. | No-op (so cue-name editing isn't disrupted). |
| `M` pressed without an active song with audio loaded. | No-op (silent). |
| Drag pin past the start or past the end of the track. | Clamp to `[0, audioBuffer.duration]`. |
| Two markers dragged to identical TC. | Allowed. Sort is stable enough; both cues exist with the same `position`. User can decide to delete one. |
| Marker selected then user clicks elsewhere (waveform, page). | Deselect (existing scrub click on the timeline triggers `deselectAllMarkers()`). |
| `Delete`/`Backspace` pressed with no marker selected. | No-op (does not affect anything else). |
| `M` pressed mid-drag of another marker. | Ignored until `mouseup` (simpler and matches user expectation). |

## Testing

**Unit (node, in existing `web/test/` harness):**

- `appendCueWithTcAndResort`: given a song with cues at TCs `[0:30, 0:10]`, appending TC `0:20` produces cues at `[0:10, 0:20, 0:30]` with `n` = `[1, 2, 3]`.
- `appendCueWithTcAndResort`: empty cues array → single cue with `n = 1`.
- `resortAndRenumber`: idempotent (running twice produces same result).

**Manual (in the desktop app):**

1. Load a track. Hit play. Press `M` four times at intervals → 4 cues appear in order with TC values.
2. Pause. Scrub back to before the first marker. Press `M` → marker drops; the new cue appears in position 1, all others renumber.
3. Drag a marker pin to a new spot → its cue's `position` updates live; on mouseup the list re-sorts if order changed.
4. Click a marker pin → it highlights; press `Delete` → cue removed, others renumber.
5. Click into a cue's name field, type `M` → letter "m" appears in the name; no marker drops.
6. Audio not loaded yet → `M` does nothing.

## Out of scope (explicitly)

- Snap-to-transient (auto-align to nearest audio peak). Future iteration.
- Arrow-key nudge of selected marker. Future iteration once drag is in.
- Undo/redo of marker operations beyond what the existing `saveState` already supports.
- Bulk marker import (e.g. from a `.cue` file or DAW marker export).
- Visual flash / sound feedback on `M` press.

## Open assumptions

- `captureCurrentPlayheadAsSmpte()` returns a TC string compatible with `timecodeToSeconds()` (round-trip safe). Verified in `audio.js` — both already used together by existing playhead/marker code.
- The cue list renderer in `render.js` rebuilds rows from `state.songs[*].cues` on every `render()` call. Confirm during implementation; if it diffs instead, may need explicit re-render after renumber.
