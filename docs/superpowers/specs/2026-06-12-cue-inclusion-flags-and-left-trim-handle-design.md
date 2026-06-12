# Cue Inclusion Flags + Left Trim Handle — Design

**Date:** 2026-06-12
**Status:** Approved
**Branch:** `feat/cue-inclusion-flags-and-left-trim-handle` (off `origin/main` `36de1da`)
**Scope:** desktop SAETTA (web/) only. iOS app untouched.

## Goal

Two related authoring-side changes to the SAETTA desktop UI:

1. Reintroduce a draggable **left trim handle** on the audio waveform —
   restoring symmetry with the existing right-end trim handle while keeping
   the body-drag model introduced in `f7852aa`.
2. Add **per-cue inclusion toggles** (`STORE` and `TC`) so the operator can
   exclude individual cues from `Send → MA` / `Export .lua` (preset stores)
   and `Send TC → MA` / `Export TC .lua` (timecode events) without deleting
   them. Useful when iterating: park a cue, ship only the rest.

Both flags default to ON so existing projects and the muscle-memory workflow
are unchanged.

## Left trim handle

### What exists today
- `trimEndHandle` (right-edge) drags `audioTrim.endS`.
- Left-edge trim (`audioTrim.startS`) is currently only adjustable by
  **body-drag** (audio-mobile / timeline-fixed model from `f7852aa`):
  grabbing the waveform shifts both `startS` and `endS` together, preserving
  segment duration.
- There is no visible left handle and no way to nudge **only** `startS`.

### Change
- New DOM element next to `trimEndHandle`:
  `<div class="trim-handle" id="trimStartHandle" title="Audio start — drag to cut the head"></div>`.
- New drag handler `onTrimStartDragDown/Move/Up` mirroring the existing
  end-handle handlers in `web/js/audio.js`.
- Drag updates only `song.audioTrim.startS`. Clamp is aligned with the
  existing audio-mobile model used by body-drag and the end handle —
  startS may go negative (audio shifted behind the timeline zero):
  `startS ∈ [-(durationS - 0.5), endSEffective - 0.5]` where
  `endSEffective = audioTrim.endS != null ? audioTrim.endS : durationS`.
  The `0.5` minimum gap matches the end handle's `leftBound = startS + 0.5`
  rule already in `audio.js:1325`.
- Body-drag stays as-is — both control paths coexist. Click priority is
  resolved the same way as on the right: a `mousedown` whose target carries
  the `trim-handle` class wins over body-drag (`audio.js` already short-
  circuits body-drag in that case — line 1243 `if (evt.target.classList
  .contains('trim-handle')) return`, so the new handle is covered by the
  same guard with no extra code).
- Visual: identical styling to the right handle (same `.trim-handle` CSS
  class, mirrored chevron). Cursor `col-resize`. Amber HUD glow consistent
  with the rest of the timeline.

### Position math
- Existing render code computes the right-handle `left` from `endS` in
  song-time projected through the viewport. The left handle uses the same
  helper with `startS` instead. Both handles re-render in the same
  `renderAudioPanel()` / waveform redraw path — no new render loop.

## Cue inclusion flags

### Data model
Each cue gains:

```js
cue.includeStore  // bool, default true
cue.includeTc     // bool, default true
```

Added to `state.js` cue construction (new cue creation paths set both to
`true`).

### Migration
`migrateState()` in `state.js`:

- For every cue lacking `includeStore`, set `includeStore = true`.
- For every cue lacking `includeTc`, set `includeTc = true`.

Old project JSONs (no flags present) therefore behave exactly as before.
SONG_1.json fixture stays loadable.

### UI — chip toggles on the cue card
- Two compact chips in the cue card header row, in line with the existing
  Amber HUD chip vocabulary used elsewhere on the desktop:
  - `STORE` chip — bound to `cue.includeStore`
  - `TC` chip — bound to `cue.includeTc`
- States:
  - **ON**: solid amber fill, dark glyph (matches active HUD CTA tone).
  - **OFF**: outline only, dim grey text, no fill.
- Click toggles. No long-press, no modifier — direct binary toggle.
- Rendered in `render.js` next to where `n`, name, fade, delay, and TC
  position already render. No separate "settings" sheet.

### Emission filtering
Single source of truth: the existing build helpers in `web/js/compile.js`.

- `buildLua(songs, headerTitle)` — when iterating cues, skip any cue with
  `includeStore === false`. The cue is omitted entirely: no `Store` line,
  no `Set ... Fade`, no `At Preset`.
- `buildCmdLines(songs)` — same skip, same condition.
- `buildTcLua(songs, headerTitle)` — when iterating cues for TC events,
  skip any cue with `includeTc === false`. The cue contributes no Event
  to the TimeRange.
- `buildTcCmdLines(songs)` — same skip, same condition.

Both filters happen **before** the existing "skip cue with no timecode
position" guard for TC. The two are independent: `includeTc = false` skips
the cue regardless of whether `position` is set; `includeTc = true` with
empty `position` still skips on the existing guard.

A song whose cues are all unchecked emits an empty body for that mode
(STORE or TC) — the song header and any trailing wrap logic still emit
correctly (zero-cue case is valid for the existing builders).

### Persistence
- `localStorage` (`cuelistCompilerProject`) — covered by the existing
  whole-state serializer; no change needed.
- Project import/export `.json` — same: the new fields are part of the cue
  object and ride along with the existing JSON round-trip.

## MA3 contract update

`shared/ma3-command-spec.md`:

- Add a short subsection under the existing emission rules noting that
  cues are filtered by `includeStore` (for preset-store paths) and
  `includeTc` (for the timecode event path) before any commands are
  emitted. Default ON, missing flag treated as ON. The MA3-side syntax is
  unchanged — only which cues participate is.

## Testing

Add to `web/test/`:

- **`tc.test.js`** — extend with a mixed-inclusion case: 3 cues, middle
  one `includeTc=false` → `buildTcLua` and `buildTcCmdLines` emit Events
  only for cues 1 and 3. Verify rawtime values and cue numbers.
- **`compile.test.js`** (new) — analogous mixed-inclusion case for the
  STORE path: `buildLua` and `buildCmdLines` skip the unchecked cue, and
  the kept cues' Store + Set lines are identical to the all-checked
  baseline.
- **Migration test** (new, in `state.test.js` if it exists, else inline in
  `compile.test.js`) — load a project JSON with cues missing both flags,
  assert post-migration cues have `includeStore=true` and `includeTc=true`,
  and the resulting Lua/cmd-lines match the all-checked baseline.

Test command: `cd web && node --test test/tc.test.js test/compile.test.js`
(per the v2.1 convention: Node `--test` doesn't accept bare directories).

## Architecture

- **Single source of truth: `web/js/compile.js`.** Both the offline `.lua`
  path and the live OSC path read from the same builders, so the filter is
  applied once and the two outputs stay in sync (the v1.5 invariant).
- **No iOS work.** iOS frontend continues to send all cues; the flags
  exist in the project JSON but iOS will ignore them on read and not write
  them on save. (Per Frank's instruction. A future iOS commit can add
  parity.)
- **No data-model migration on iOS save:** if Frank exports a project from
  the desktop with flags, imports on iOS, and re-exports back to the
  desktop, the flags must **not** be silently stripped. iOS's existing
  project save is JSON-passthrough of unknown fields (per the v2.0 Kit
  model design, fields it doesn't recognise survive round-trip). If that
  assumption turns out to be wrong on real testing, the fallback is to
  treat any cue without flags as `includeStore=true` / `includeTc=true`
  on desktop load (which the migration already does), so a strip-on-iOS
  round-trip degrades to "all included" — the safe default.

## Out of scope

- Bulk toggle (e.g. "uncheck all TC for this song"). Frank can re-request
  if it becomes a pain in real use.
- Visual indicator on the timeline waveform that a cue is excluded.
- TC handle on the timeline that mirrors the chip state. (The chip lives
  on the cue card; the timeline marker behavior is unchanged.)
- iOS UI parity.
- A "soft skip" mode that emits the cue but with values cleared. Excluded
  cues are simply omitted.

## Open risks

- Possible visual collision with the existing Amber HUD chip cluster on
  the cue card if the card already crowds horizontally at narrow widths.
  Mitigation: chips wrap to a second row at narrow widths using the same
  pattern as elsewhere on the desktop.
- If iOS's JSON round-trip *does* strip unknown fields, an iOS save would
  destroy the flags. Caught only on real testing — the migration on the
  desktop side handles the degradation gracefully (re-treats as all ON).
