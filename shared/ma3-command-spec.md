# MA3 Command Contract

The single source of truth for the grandMA3 command sequence Cuelist Compiler
emits. **Both** frontends implement this identically:

- Web: `web/js/compile.js` — `buildLua()` (exported `.lua` plugin) and
  `buildCmdLines()` (live OSC). `compile.js` is the executable reference.
- iOS: the native Swift command builder (to be written) must reproduce it.

> **Rule:** any change to the sequence updates this file **and** `web/js/compile.js`
> in the same pull request. They must never diverge.

## Pool numbers

| Pool | Number |
|------|--------|
| dimmer | 1 |
| position | 2 |
| gobo | 3 |
| color | 4 |
| beam | 5 |
| focus | 6 |

## Store mode

A show is stored with one flag, chosen by the user:

- `/Overwrite` (default)
- `/Merge`

Every `Store` also carries `/NoConfirmation`.

## Per-cue sequence

For each song (in show order), for each cue (sorted ascending by cue number):

1. `ClearAll`
2. For each **group block** whose group name is non-empty:
   - `Group "<groupName>"`
   - For each of the 6 pools, in order `color, dimmer, position, gobo, beam, focus`,
     whose preset name is non-empty:
     - `At Preset <poolNumber>."<presetName>"`
     - If a fade value resolves (see Fade/Delay resolution): `Fade <f> FeatureGroup <poolNumber>`
     - If a delay value resolves: `Delay <d> FeatureGroup <poolNumber>`
3. Store the cue:
   - With a cue name: `Store Sequence <seq> Cue <n> "<cueName>" <FLAG> /NoConfirmation`
   - Without a cue name: `Store Sequence <seq> Cue <n> <FLAG> /NoConfirmation`
4. If the cue has a fade: `Set Sequence <seq> Cue <n> Fade <f>`
5. If the cue has a delay: `Set Sequence <seq> Cue <n> Delay <d>`

After all songs and cues: a final `ClearAll`.

## Fade / Delay resolution

Per preset attribute, the value used is:

1. The preset's own `fade`/`delay` if non-empty, else
2. The per-pool default (`defaults[pool].fade` / `.delay`) if non-empty, else
3. Omitted (no `Fade`/`Delay` line emitted).

Cue-level `fade`/`delay` have no default fallback — emitted only if set on the cue.

## String escaping

Group, preset, and cue names have `"` replaced with `\"`. Names are trimmed.

## Notes

- `buildLua()` wraps this sequence in a Lua plugin that calls `Cmd(...)` per line
  and prints progress; `buildCmdLines()` returns the raw command strings for OSC.
  Both must produce the **same ordered command list**.
- The live-OSC path requires MA3 OSC **Echo Input = Yes** for `/cmd` to dispatch.

## Timecode show per song (optional)

Independent from the sequence/cue command sequence above. Driven by the
`Send TC ...` toolbar buttons and `buildTcCmdLines` / `buildTcLua`.

### Pre-conditions (operator manual on MA3, once per song)

- Sequence `<N>` exists with cues.
- Timecode pool `<N>` exists.
- Track at `Timecode <N>.1.1` has `target = Sequence <N>`.

### Per-song sequence

For each song with at least one cue having a `position` matching SMPTE
`HH:MM:SS:FF` (validated by `isValidSmpte`, `FF < 25` since 25 fps), with
`<N>` = song's `sequence`:

1. **Cleanup** (Overwrite-only):
   - `Delete Timecode <N>.1.1.1.1.1 /NoConfirmation` × 200

   Each Delete pops the first event in the SubTrack. Excess deletes after the
   SubTrack is empty fail silently on MA3.

2. **Events** — for each cue with valid `position`, ascending by `cue.n`,
   indexed by `i` starting from 1:
   - `Store Timecode <N>.1.1.1.1 'Goto Cue <c.n> Sequence <N>' /NoConfirmation`
   - `Set Timecode <N>.1.1.1.1.<i> Property 'time' <secondsFloat>`

   `<secondsFloat>` = SMPTE→seconds at 25 fps:
   `(HH * 3600) + (MM * 60) + SS + (FF / 25)`

### Notes

- The `time` property is in seconds (float). NOT SMPTE string, NOT ticks.
- `Property` keyword + lowercase property name is required. The bare
  `Set ... Time <v>` keyword is parsed as a sub-noun (`Time Executor`) — wrong.
- Merge mode is NOT supported for TC events in v1: no way to discover the
  next event index via Cmd-line without Lua. Toggle in toolbar applies only
  to sequences.
- `buildTcLua` wraps the same lines in `Cmd(...)` calls; `buildTcCmdLines`
  returns the raw strings for OSC. Both must produce the same ordered list.
