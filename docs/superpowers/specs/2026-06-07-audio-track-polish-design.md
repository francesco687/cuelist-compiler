# Audio track polish — transport, ruler, TC reader, red markers, non-destructive trim

**Date:** 2026-06-07
**Status:** Approved (brainstorm) → ready for implementation plan
**Scope:** `web/` only. No hub, OSC, or iOS changes.

## Goal

Make the per-song audio panel a tool an operator can actually program against:

1. Real transport (Stop, skip prev/next marker, Restart) instead of the single Play↔Pause toggle.
2. A time ruler above the waveform so you can read where you are without scrubbing.
3. A big SMPTE readout (`HH:MM:SS:FF`) of the current playhead, anchored to the song's in-point so it matches what the 🎯 cue-capture button writes.
4. Red markers (the existing yellow blurs into the waveform); playhead recoloured white so it stays visible on red markers.
5. Non-destructive **in-point / out-point** trim handles so the operator can ignore leading silence / trailing applause and align SMPTE 0:00 to the actual song start.

All five ship as one polish pass on `web/js/audio.js` + a small CSS reskin. Lua plugin, OSC, hub, iOS untouched.

## Non-goals

- **Destructive audio editing.** No re-encoding, no exporting a trimmed file. The original audio stays as-is in `audioCache`.
- **Bulk SMPTE shift** on all cues. The trim handles change where the song *starts in the file*; they do not rewrite stored `cue.position` SMPTEs.
- **Zoom on the waveform.** Ruler is fixed to the visible timeline width.
- **Per-channel ruler / per-channel markers.** Ruler renders once above both channels.
- **iOS parity.** This is a programming-time tool on the web/desktop side; iOS Live tab is for runtime.

## Decisions (locked during brainstorm)

| Question | Decision |
|---|---|
| Transport buttons | `⏮ ⏹ ⏯ ⏭ ↻` — prev-marker / stop / play-pause / next-marker / restart |
| Stop behaviour | `pause()` + `currentTime = trim.startS` |
| Restart behaviour | `currentTime = trim.startS`, keep playing if was playing |
| Skip prev/next | Jumps to the nearest cue marker (file time = `trim.startS + smpteToSeconds(cue.position)`). "Prev" is the marker strictly before current; "next" strictly after. No wrap-around. |
| Marker base colour | `rgba(220, 60, 60, 0.55)` |
| Marker hover | `rgba(255, 80, 80, 1)`, width 2px |
| Marker selected | solid `#ff5050` + halo `box-shadow: 0 0 4px rgba(255,80,80,0.8)` |
| Marker current | solid `#ff5050` with white border (`border-left: 2px solid #fff`) — kept visually distinct from selected |
| Marker label | white text on `rgba(120, 30, 30, 0.85)` background |
| Playhead colour | `#f8f8f8` (was `#ff5a5a`) |
| Ruler position | Above L/R waveforms, height 18px |
| Ruler tick policy | Auto-pick interval from duration: ≤30s → 1s ticks (major every 5s); ≤2min → 5s (major every 30s); >2min → 10s (major every 60s) |
| Ruler renderer | Single `<canvas id="ruler">`, redrawn on resize / song-swap / trim change |
| Ruler dimming | Outside trim window: tick + label `#333` instead of `#888` |
| TC reader format | `HH:MM:SS:FF`, monospace bold ~22px |
| TC reader anchor | Shows `audioEl.currentTime − trim.startS`. Matches what 🎯 captures. |
| TC reader colour | `#fff` inside trim window; `#888` before `startS`; `#ff5a5a` after `endS` |
| TC reader sublabel | `(M:SS / M:SS)` of active segment (`endS − startS`), font `#888` ~11px |
| Trim model | `song.audioTrim = { startS: 0, endS: null }`. `null` `endS` = end-of-file. |
| Trim UI | Two draggable handles at timeline left/right edges. Hit area 8px, visual 4px. |
| Trim dim overlay | Outside-window: black at 60% opacity over both wave canvases + ruler. |
| Trim auto-pause | When `audioEl.currentTime ≥ trim.endS` and `endS != null`, `pause()` and clamp to `endS`. |
| Trim seek clamp | Clicks on the timeline clamp to `[startS, endS]`. |
| Persistence | `song.audioTrim` is in `state.songs[i]` → saved in localStorage and exported in project JSON. Backwards-compat via `migrateState`: missing → `{startS:0, endS:null}`. |

## Data model

Per-song addition (in `state.songs[i]`):

```js
song.audioTrim = {
  startS: 0,      // in-point in original-file seconds. Default 0.
  endS: null      // out-point. null = end of file. Always > startS when non-null.
};
```

No new top-level state. No global preference. Trim is per-song because each song's audio is different.

### Migration

In `migrateState()` (existing in `state.js`):

```js
song.audioTrim = song.audioTrim || { startS: 0, endS: null };
```

Existing `SONG_1.json` and any other project files load cleanly with default trim (no visible change).

### Project JSON

`exportProject()` already serialises `state.songs` whole — no change needed. `audioTrim` will round-trip automatically.

## Timing semantics

This is the core contract. Get this right and everything else follows.

- `audioEl.currentTime` is **file time** (raw, what the `<audio>` element reports).
- `cue.position` is a SMPTE string **relative to song start** (in-point).
- **Song time** = `audioEl.currentTime − trim.startS`. This is what the TC reader displays, what 🎯 captures, what the ruler labels.
- **File time of a cue** = `trim.startS + smpteToSeconds(cue.position)`. This is where its marker is drawn on the waveform and where skip-to-marker seeks to.

Moving the in-point shifts every marker visually (because their file-time positions change) but leaves cue SMPTEs untouched. That is the intended "spostare" semantic: the operator is aligning the audio file under a stable cue list, not nudging the cues.

The 🎯 button continues to call `captureCurrentPlayheadAsSmpte()`, which now becomes:

```js
return secondsToTimecode(audioEl.currentTime - song.audioTrim.startS);
```

So 🎯 inside the trim window writes 0-based SMPTE consistent with the operator's mental model.

## Layout

Top to bottom inside `#audioPanel`:

```
┌────────────────────────────────────────────────────────────────┐
│ [⏮ ⏹ ⏯ ⏭ ↻]  [L][R]  song.mp3            00:00:05:15          │
│                                            ─────────            │
│                                            0:05 / 3:24          │
├────────────────────────────────────────────────────────────────┤
│ 0:00     0:05     0:10     0:15     0:20    ← ruler (canvas)   │
├═══════════════ ═══════════════════════════════════ ════════════┤  ← dim
│ L  ▁▃▅▇▆▅▄▂▁▂▄▅▇▆▄▃▁▁▂▄▆▇▆▄▂▁                                  │
│ R  ▁▂▄▆▅▄▃▁▁▂▃▅▆▅▃▂▁▁▃▅▇▆▄▂▁▁                                  │
│   ↑                                                  ↑          │
│  in-handle    │ │ │  ← marker rossi             out-handle      │
│                                  │ ← playhead (bianco)          │
└────────────────────────────────────────────────────────────────┘
```

(The `═════ ════` shading above the ruler row in the diagram is the trim dim overlay. Real implementation: a single overlay div per dead zone, spanning ruler + both wave rows, `background: rgba(0,0,0,0.6)`, `pointer-events:none`.)

DOM under `#timeline`:

```
#timeline
  canvas#ruler            (height 18px)
  div.channel-wave > canvas#waveL
  div.channel-wave > canvas#waveR    (if stereo)
  div.markers
    div.marker × N
  div.playhead
  div.trim-dim.left       (absolute, 0 → startS px)
  div.trim-dim.right      (absolute, endS → 100% px)
  div.trim-handle.left
  div.trim-handle.right
```

## Behaviour details

### Skip prev/next marker

- Source list: cues with parseable `cue.position`, sorted by SMPTE seconds ascending, filtered to those whose file-time falls inside `[trim.startS, trim.endS or duration]`.
- `now = audioEl.currentTime - trim.startS` (song time).
- **Prev**: largest cue SMPTE strictly less than `now − 0.25s` (the 250 ms tolerance prevents bouncing off the marker you're sitting on). If none, seek to `trim.startS`.
- **Next**: smallest cue SMPTE strictly greater than `now + 0.05s`. If none, no-op (stay put — don't jump to end).
- Result: `audioEl.currentTime = trim.startS + smpteToSeconds(targetCue.position)`. Playing state unchanged.

### Stop

`audioEl.pause(); audioEl.currentTime = trim.startS;` Always. Even if already paused.

### Restart

`const wasPlaying = !audioEl.paused; audioEl.currentTime = trim.startS; if (wasPlaying) audioEl.play();`

### Auto-pause at out-point

In the existing `updatePlayhead` rAF loop, add at the top:

```js
if (trim.endS != null && audioEl.currentTime >= trim.endS && !audioEl.paused) {
  audioEl.pause();
  audioEl.currentTime = trim.endS;
}
```

(Clamping to `endS` prevents the playhead from sitting one frame past the out-point.)

### Trim handle drag

- `mousedown` on a handle starts a drag, sets `document.body.style.cursor='ew-resize'`.
- `mousemove` translates pixel-x to file seconds via `duration`, clamps:
  - Left handle: `[0, (endS ?? duration) − 1.0]` — keep at least 1 second of window
  - Right handle: `[startS + 1.0, duration]`
- Update `song.audioTrim` live, redraw markers + ruler + dim overlay + playhead each frame.
- `mouseup` calls `saveState()` and `render()` once.
- Double-click on a handle: reset that side (`startS=0` or `endS=null`).

### Click-to-seek

Click on the timeline (outside marker / handle hit areas):

```js
const clicked = pct * duration;
const clamped = Math.max(trim.startS, Math.min(trim.endS ?? duration, clicked));
audioEl.currentTime = clamped;
```

(Existing behaviour was `[0, duration]`; new behaviour clamps to trim window.)

### Ruler canvas

- Width: `tl.clientWidth` (sync with waveform canvases on `ResizeObserver`).
- Height: 18px fixed.
- Redraw triggers: song swap, audio load, trim change, container resize.
- Pick `tickInterval` and `majorEvery` from `duration` per the table above.
- For each tick from 0 to `duration` step `tickInterval`:
  - x = `(t / duration) * width`
  - draw 1-px vertical line, height 6 (minor) or 10 (major)
  - if major: `fillText(formatMMSS(t), x + 2, 14)`
  - colour: `#888` if `startS ≤ t ≤ (endS ?? duration)` else `#333`
- Font: `10px ui-monospace, Consolas, monospace`.

### TC reader

- Element: `<span id="tcReader">00:00:00:00</span>` + `<span id="tcReaderSub">0:00 / M:SS</span>`.
- Updated every frame from `updatePlayhead`:
  ```js
  const songT = audioEl.currentTime - trim.startS;
  tcReader.textContent = secondsToTimecode(Math.max(0, songT));
  tcReader.style.color =
    audioEl.currentTime < trim.startS ? '#888' :
    (trim.endS != null && audioEl.currentTime > trim.endS) ? '#ff5a5a' :
    '#fff';
  ```
- Subline: `${secondsToMMSS(Math.max(0, songT))} / ${secondsToMMSS((trim.endS ?? duration) - trim.startS)}`.
- Replaces the existing small `#audioTime` `<span>`.

## Edge cases & fall-throughs

| Case | Behaviour |
|---|---|
| No audio loaded | Existing empty state. No transport, no ruler, no TC reader. |
| `endS != null` and a cue's file-time is past `endS` | Marker still renders (operator might want to drag it back into the window). Skip-next ignores it. Auto-pause doesn't care. |
| `startS > 0` and a cue's file-time is before `startS` | Same — render but don't include in skip. |
| Drag handle into a position with no cues inside the window | Allowed. Window can be empty. Skip-next/prev seeks to `startS` or no-ops. |
| Operator hits ⏭ at end of song | No-op (don't jump). |
| Operator hits ⏮ at start of song | Seek to `trim.startS`. |
| `cue.position` is empty / unparseable | Skipped by transport, not drawn as marker. (Existing behaviour.) |
| Song swap while playing | Existing behaviour: previous audio pauses, new song's trim applies. |
| Project import with old JSON (no `audioTrim`) | `migrateState` injects `{startS:0, endS:null}`. No visible change. |

## File touch list

| File | Change |
|---|---|
| `web/js/state.js` | Add `audioTrim` migration in `migrateState`; nothing else. |
| `web/js/audio.js` | Bulk: transport bar markup + handlers, ruler canvas + draw fn, TC reader update, trim handle drag, auto-pause + click clamp, capture function adjustment, marker file-time math through `trim.startS`. |
| `web/css/styles.css` | Marker palette (red), playhead colour (white), transport button row, ruler row, trim handles + dim overlay, TC reader typography. |
| `web/index.html` | Zero. Panel is fully rendered by `audio.js`. |
| `examples/SONG_1.json` | No change. Loads with default trim. |
| `web/test/transport.test.js` | Add cases for skip-prev/next-marker, stop, restart, auto-pause, click clamp. (Existing test file. See note below.) |

`compile.js`, OSC, Lua templates, hub, iOS, ma3-command-spec.md, plugins: **untouched**. This is purely a programming-time editor change.

## Testing

Unit tests under `web/test/`:

- `transport.test.js` (extend existing):
  - `findPrevMarker(now, cues, trim)` returns expected cue
  - `findNextMarker(now, cues, trim)` returns expected cue
  - prev/next handle the 250 ms tolerance correctly
  - prev returns null → caller seeks to `startS`
  - next returns null → caller no-ops
- New `trim.test.js`:
  - `pickTickInterval(duration)` returns the right interval/major per the table
  - file→song time conversion is round-trip clean with non-zero `startS`
  - auto-pause condition: `shouldAutoPause(currentTime, trim)` returns true past `endS`, false inside, false when `endS=null`
  - click-clamp: `clampSeek(rawSeconds, trim, duration)` clamps to `[startS, endS or duration]`

Test command: `cd web && node --test test/transport.test.js test/trim.test.js`.

Manual smoke (operator-facing):
- Load `examples/SONG_1.json` and its referenced audio.
- Drag in-point to 1.5s. Confirm: markers visually slide right; TC reader shows negative→`00:00:00:00` as playhead crosses in-point; 🎯 at playhead = 1.5s writes `00:00:00:00`.
- Drag out-point to 2 minutes. Confirm: auto-pause when playback reaches that point.
- Press ⏭ repeatedly: visits each marker in order, stops at last.
- Press ↻ during playback: jumps to in-point, keeps playing.
- Reload page → trim persists.

## Open questions

None. All decisions locked above.

## Out of scope (next time)

- Keyboard shortcuts (`space` for play/pause, `[` / `]` for trim in/out, `n`/`p` for next/prev marker). Easy add later.
- Zoom on the waveform.
- Trim-point capture from current playhead (a one-click "set in to current" / "set out to current" button).
- Cross-song global SMPTE offset (a "the whole show is shifted by 0.5s" preference).
