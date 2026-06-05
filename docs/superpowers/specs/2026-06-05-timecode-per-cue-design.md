# Timecode per Cue — Design

**Status:** Ready for implementation
**Date:** 2026-06-05
**Scope:** Add SMPTE timecode per cue + push to grandMA3 Timecode pool

## Goal

Let the operator attach a SMPTE position to each cue in the compiler, and
push those positions to grandMA3 as Timecode events that fire the matching
`Goto Cue <n> Sequence <s>` at the right moment. Single button: `Send TC
current → MA` / `Send TC all → MA`, parallel to the existing Send for
sequences.

## Conventions (locked)

- **TC pool number == Sequence number == song "main number".** No separate
  field. A song with `sequence: 12` writes to Timecode pool `12`.
- **Frame rate: 25 fps** (PAL/EBU). Hard-coded in v1; constant in `constants.js`
  if v2 needs to change it.
- **SMPTE format: `HH:MM:SS:FF`.** Same as CuePoints `Position` column. Stored
  as-is in `cue.position` (existing field).

## User preconditions (manual setup on MA3, once per song)

The compiler does NOT auto-create the Track inside the TC pool. The operator
sets this up once per song before pressing Send TC:

1. **Sequence N exists with cues** — already true after the regular Send for
   sequences.
2. **Timecode pool N exists** — created interactively on MA3, or by the
   compiler's first Send TC (which issues `Store Timecode N`).
3. **Track inside TC pool N targets Sequence N** — operator drags Sequence
   N onto the TC pool slot N in MA3. This creates the Track at path
   `Timecode N.1.1` with `target = Sequence N`.

Why manual: no Cmd-line was found to create the Track + assign target in one
step. Adding it would require Lua, which we chose to defer per (I) in the
discussion.

Document this clearly in the compiler README and surface a UI hint in the
TC send buttons ("⚠ pre-create Track in TC pool first").

## Data model

**Zero new fields.** The existing `cue.position` field (already populated
from CuePoints CSV import) is the source of truth.

```js
cue = {
  n: number,
  name: string,
  actions: [...],
  fade: string,
  delay: string,
  collapsed: boolean,
  position: string,   // ← "HH:MM:SS:FF" or "" — already exists
}
```

Migration: `migrateCues` already initializes `position = ''` when missing
(state.js:68). No change.

## UI

### Per-cue: TC field + capture button

In each cue card header (`render.js`), inline with N and name:

```
[N: 3]  [TC: 00:00:47:16 🎯]  [name: VERSE]  [fade:  ]  [delay:  ]
```

- **TC input**: monospace font, 11 characters width, validated on blur.
- **Validation regex**: `^(\d{2}):(\d{2}):(\d{2}):(\d{2})$` with constraints
  `MM<60`, `SS<60`, `FF<25` (since 25 fps).
- **Empty value is valid** — means "this cue has no TC; excluded from export".
- **Invalid value is saved** (don't block editing) but rendered with red
  border + tooltip "Invalid SMPTE — excluded from TC export".
- **`🎯` button**: capture-from-playhead (see Capture section).

### Per-song: "no TC" badge

If `cue.position === ''`, append a small grey badge `no TC` next to the cue
number. Helps the operator spot which cues will be skipped on Send TC.

### Toolbar: 2 new buttons

Next to existing Send buttons:

```
[ Send current → MA ]  [ Send all → MA ]  [ Send TC current → MA ]  [ Send TC all → MA ]
                                          └────────────── new ──────────────────────┘
```

Tooltip on each TC button: "Pre-create Track in TC pool first. Overwrites
existing events."

## Capture from playhead

`🎯` click handler in render.js calls a helper from audio.js:

```js
function captureCurrentPlayheadAsSmpte() {
  if (!audioEl || isNaN(audioEl.currentTime)) return null;
  return secondsToSmpte25(audioEl.currentTime);
}

function secondsToSmpte25(t) {
  const H  = Math.floor(t / 3600);
  const M  = Math.floor((t % 3600) / 60);
  const S  = Math.floor(t % 60);
  const FF = Math.floor((t - Math.floor(t)) * 25);
  const pad = n => String(n).padStart(2, '0');
  return `${pad(H)}:${pad(M)}:${pad(S)}:${pad(FF)}`;
}
```

UX:
- If no audio loaded for active song → button disabled + tooltip
  "Load audio first".
- If audio loaded → captures `audioEl.currentTime`, writes into the cue's
  `position`, `saveState()`, re-render.

## MA3 command contract — TC events

To be appended to `shared/ma3-command-spec.md` as a new section
`## Timecode show per song (optional)`.

### Preconditions (verified per song manually)

```
Sequence <N> exists with cues
Timecode pool <N> exists
Timecode pool <N> has a Track at index .1.1 with target = Sequence <N>
```

### Send TC sequence (per song)

For each song in scope, with `<N>` = song's `sequence`:

**Phase 1 — cleanup (Overwrite-only behavior):**

```
Delete Timecode <N>.1.1.1.1.1 /NoConfirmation
Delete Timecode <N>.1.1.1.1.1 /NoConfirmation
... (repeat 200 times)
```

Each delete pops the first event. Excess deletes after the SubTrack is
empty fail silently (MA3 swallows the no-op). 200 = generous upper bound
(typical songs have 20-40 cues).

**Phase 2 — add events:**

For each cue with valid `position`, sorted ascending by `cue.n`, indexed by
i starting from 1:

```
Store Timecode <N>.1.1.1.1 'Goto Cue <c.n> Sequence <N>' /NoConfirmation
Set Timecode <N>.1.1.1.1.<i> Property 'time' <secondsFloat>
```

Where `<secondsFloat>` = SMPTE→seconds float at 25 fps:

```js
function smpteToSecondsFloat25(smpte) {
  const m = /^(\d{2}):(\d{2}):(\d{2}):(\d{2})$/.exec(smpte);
  if (!m) return null;
  const [_, h, mm, s, ff] = m;
  return (+h) * 3600 + (+mm) * 60 + (+s) + (+ff) / 25;
}
```

### Throttling

Same 20 ms between commands (`OSC_SEND_INTERVAL_MS` in transport.js).
For a 40-cue song: 200 deletes + 80 cmds (Store + Set per cue) ≈ 280 cmds
× 20 ms ≈ 5.6 seconds. Acceptable.

Optimization for v2 (not v1): skip deletes if we can query existing count
first via a one-shot Lua read.

## Compiler pipeline

### `web/js/compile.js` extensions

Add two new exported helpers, mirroring the existing pair:

```js
function buildTcCmdLines(songs) { ... }   // returns string[] of OSC cmds
function buildTcLua(songs)      { ... }   // returns full Lua plugin source
```

Both share a single internal `tcSequenceFor(song)` helper that produces the
ordered command list described above.

`buildTcLua` wraps each command in `Cmd('...')` calls inside the plugin's
`main()` loop, so the existing `.lua` export workflow (paste-into-plugin)
gets TC events for free.

### Wiring

- `web/js/main.js` (or wherever Send buttons are wired): add 2 new buttons
  `Send TC current → MA` and `Send TC all → MA`. Each invokes
  `buildTcCmdLines([song])` or `buildTcCmdLines(state.songs)`, then sends via
  existing OSC transport.

- `buildLua()` and `buildCmdLines()` (existing) remain unchanged. The new
  TC functions are a parallel path — TC events are NOT bundled into the
  sequence cue commands. Operator chooses what to send.

## Updates to `shared/ma3-command-spec.md`

Add at the end:

```markdown
## Timecode show per song (optional)

Pre-conditions (operator sets up once per song on the desk):
- Sequence `<N>` exists with cues
- Timecode pool `<N>` exists
- Track at `Timecode <N>.1.1` has `target = Sequence <N>`

For each song with at least one cue having a valid `position`, with
`<N>` = song's `sequence`:

1. **Cleanup** (Overwrite-only behavior):
   - `Delete Timecode <N>.1.1.1.1.1 /NoConfirmation` × 200
2. **Events**: for each cue with valid `position`, ascending by `cue.n`,
   indexed by `i` from 1:
   - `Store Timecode <N>.1.1.1.1 'Goto Cue <c.n> Sequence <N>' /NoConfirmation`
   - `Set Timecode <N>.1.1.1.1.<i> Property 'time' <secondsFloat>`

`<secondsFloat>` = SMPTE→seconds at 25 fps:
`(HH * 3600) + (MM * 60) + SS + (FF / 25)`

The `time` property is in seconds (float), NOT SMPTE string, NOT ticks.
`Property` keyword is required for `Set`; the property name is lowercase
`time`. The bare `Set ... Time` keyword is parsed as a sub-noun
(`Time Executor`), NOT as a property setter — confirmed wrong on 2026-06-05.

`buildTcLua()` wraps the same command list in `Cmd(...)` calls;
`buildTcCmdLines()` returns the raw strings for OSC. Both must produce the
same ordered list.
```

## Edge cases

| Case | Behavior |
|---|---|
| Cue with empty `position` | Excluded from TC export. Badge `no TC` in UI. |
| Cue with invalid SMPTE | Excluded + warning logged in UI ("invalid TC on cue X — skipped"). |
| Song with zero valid TC cues | Send TC is a no-op + UI message "no TC events to send for SONG". |
| `🎯` clicked but no audio loaded | Button disabled with tooltip "Load audio first". |
| `🎯` clicked, audio paused at 0 | Captures `00:00:00:00` (valid). |
| FF >= 25 in user input | Invalid → red border + excluded. |
| TC pool N doesn't exist on MA3 | Send fails silently per command (MA3 doesn't ACK over OSC). UI shows generic "TC send done" without verifying. Operator's responsibility per preconditions. |
| Track at .1.1 doesn't exist | Same as above — events fail to land. |
| Cmd `Set Timecode .. Property 'time' 0.0` (zero) | Valid; event at 0s. |

## Out of scope for v1 (explicit NO)

- **Merge mode for TC events**: forced Overwrite. Toggle in toolbar stays
  visible for sequences but TC ignores it. Tooltip on TC button explains.
- **Multi-fire** (same cue at multiple TC values): 1 cue = 1 TC value.
  Workaround: duplicate the cue with a different `n`.
- **Edit-on-waveform** (click on waveform to set cue TC): out. Maybe v2.
- **Frame rate ≠ 25 fps**: hard-coded in `constants.js`. Editable only via
  source for v1.
- **Auto Track creation in TC pool**: operator drags manually. Maybe v2 via
  Lua.
- **TC pool naming / Duration / source config**: out of compiler scope.
- **Reading current MA3 TC state** (verify before send, show diff): out.

## Testing strategy

### Golden fixture

Add to `examples/SONG_1.json` an enriched variant with TC positions, and a
matching `examples/SONG_1.tc.cmdlines.txt` golden file produced by
`buildTcCmdLines([song1])`. Regression test: hub or web test runner
compares output to golden.

### Manual UAT (operator flow)

1. Load `examples/SONG_1.json`
2. On MA3 onPC: Store Sequence with cues, create TC pool, drag sequence
   onto TC pool (per preconditions)
3. In compiler: verify TC values appear in cue cards
4. Click `Send TC current → MA`
5. On MA3: open TC pool, verify N events at expected times
6. Run the TC show → cues fire at the expected timestamps

### Edge case probes

- Send with one cue having invalid TC → check UI warning + that cue skipped
- Send to a TC pool with no Track → events don't land, no crash
- Use `🎯` button to capture from playhead → verify written value

## Implementation order (rough)

1. `state.js`: add validation helper + regex + Smpte conversion utilities
2. `audio.js`: add `captureCurrentPlayheadAsSmpte()`
3. `render.js`: add TC input + 🎯 button to cue card; add "no TC" badge
4. `compile.js`: add `buildTcCmdLines` + `buildTcLua` with shared internal
5. `main.js`: wire 2 new toolbar buttons
6. `shared/ma3-command-spec.md`: append the new section
7. Add golden fixture + test
8. Document preconditions in README

## Lessons captured from exploration on 2026-06-05

Worth recording so future-us doesn't re-discover:

- **Cmd-line CAN create TC events** at the deep `<pool>.1.1.1.1` path,
  contradicting initial forum research that said "events are Lua-only".
  The trick is the deep dot notation and `Property 'time'` syntax.
- **`Set ... Time` (bare keyword) is wrong** — MA3 parses `Time` as a
  sub-noun (`Time Executor`), not as a property accessor. Always use
  `Set <obj> Property 'time' <value>`.
- **`time` property is in float seconds**, not ticks (1/16777216 sec).
  Inspector confirms `time=5.000000` for our `Property 'time' 5` write.
- **Property names are lowercase** in the object model (`time`, `name`,
  `target`). The CLI may accept some title-case via auto-correction but
  lowercase is the canonical form.
- **Playhead positioning via Cmd is broken** — `Goto Timecode N Time T`,
  `Set Timecode N Property 'PlaybackTime' T`, and `Store .. /time=T` all
  failed (silently moved playhead to garbage values). This forces the
  Store+Set-Property-by-index pattern, which is why Merge mode is
  Lua-only.
