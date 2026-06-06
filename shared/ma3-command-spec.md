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
6. If the cue has a non-empty note: `Set Sequence <seq> Cue <n> "Note" "<note>"`

After all songs and cues: a final `ClearAll`.

## Fade / Delay resolution

Per preset attribute, the value used is:

1. The preset's own `fade`/`delay` if non-empty, else
2. The per-pool default (`defaults[pool].fade` / `.delay`) if non-empty, else
3. Omitted (no `Fade`/`Delay` line emitted).

Cue-level `fade`/`delay` have no default fallback — emitted only if set on the cue.

## String escaping

Group, preset, and cue names have `"` replaced with `\"`. Names are trimmed.

Cue notes are collapsed to a single line (newlines/tabs/whitespace runs → one
space), trimmed, and `"` replaced with `\"`. A note that is empty or
whitespace-only emits no command, leaving the desk's existing Note field
untouched.

## Notes

- `buildLua()` wraps this sequence in a Lua plugin that calls `Cmd(...)` per line
  and prints progress; `buildCmdLines()` returns the raw command strings for OSC.
  Both must produce the **same ordered command list**.
- The live-OSC path requires MA3 OSC **Echo Input = Yes** for `/cmd` to dispatch.
