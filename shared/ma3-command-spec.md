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

## Cue inclusion filters

Cues carry two optional boolean flags in the project JSON:

- `includeStore` — when `false`, the cue is omitted from the Store path
  (no `ClearAll`, no `Group`, no `At Preset`, no `Store`, no `Set ... Fade/Delay/Note`).
- `includeTc` — when `false`, the cue is omitted from the Timecode show path
  (no Event is appended on the TimeRange's CmdSubTrack).

Missing flags are treated as `true` (the desktop-side migration fills them
in). The two filters are independent and combine with AND: a cue with
`includeStore=false` and `includeTc=true` still produces a TC event but no
Store. The MA3-side syntax is unchanged — only the set of participating
cues changes.

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

## Timecode show per song (optional)

Independent from the sequence/cue command sequence above. Driven by the
`Send TC ...` toolbar buttons and `buildTcCmdLines` / `buildTcLua`.

> **History note** — an earlier version of this spec (2026-06-05) used a
> command-line-only approach (`Store Timecode <N>.1.1.1.1 'Goto Cue ...'`
> + `Set ... Property 'time' ...`). That approach is INVALID: MA3's
> command-line `Store Timecode <path>` only creates pool entries /
> TrackGroups / Tracks, not Events — attempts return "Cannot Create
> Object". Events on MA3 are only addressable via the **Lua Object API**
> (forum thread 68641). The current spec replaces that path entirely.

### Pre-conditions (operator manual on MA3, once per song)

- Sequence `<N>` exists with cues.
- Timecode pool `<N>` exists.
- TC `<N>` has at least one TrackGroup, whose first Track targets `Sequence <N>`.

### Object hierarchy

```
DataPool().timecodes[N]
  └─ TrackGroup (Children()[1])
       └─ Track (tg[2], target = Sequence N)   -- tg[1] is an internal pseudo-track;
                                               --   user Track sits at index 2
            └─ TimeRange (Acquire())
                 └─ CmdSubTrack (Acquire('CmdSubTrack'))
                      └─ Event (Acquire())  -- one per cue
                           - rawtime         : integer, internal units (1 s = 16777216)
                           - cuedestination  : Cue handle (set via GetObject)
```

### Per-song sequence

For each song with at least one cue having a `position` matching SMPTE
`HH:MM:SS:FF` (validated by `isValidSmpte`, `FF < 25` since 25 fps), with
`<N>` = song's `sequence`:

The compiler emits **one** OSC command per song:

```
Lua "<single-line Lua code>"
```

The Lua code performs (in order):

1. **Resolve** Sequence `<N>` and Timecode pool entry `<N>`. Bail if either missing.
2. **Locate** TrackGroup `Children()[1]` and Track `tg[2]` (not `tg[1]` — that index
   is an internal pseudo-track whose events visually attach to the TG header row in
   the Timecode editor instead of the user's Sequence-targeted Track). Bail if either missing.
3. **Build send set**: `sendNos[c[1]] = true` for each cue in the send list (O(1)
   lookup table keyed by cue number).
4. **Reuse existing CmdSubTrack**: walk `tr:Children()` to find the first existing
   `CmdSubTrack`. Only `Acquire()` a fresh TimeRange + CmdSubTrack if the Track has
   no existing events at all. Prevents orphan TimeRanges accumulating across repeated sends.
5. **Selective delete**: for every TimeRange → CmdSubTrack → Event on the Track,
   delete (via reverse iteration + `sb:Delete(i)`) only events whose
   `cuedestination.no` is in `sendNos`. Events for cues **not** in the send list are
   never touched. Do **not** delete the TimeRanges themselves — see Delete notes.
6. **Write events**: for each cue in the send list:
   - `:Acquire()` a new Event under the reused (or freshly created) CmdSubTrack.
   - `Set('rawtime', round(seconds * 16777216))`.
   - `cue = GetObject('Sequence <N> Cue <cue.n>')`; if truthy, `Set('cuedestination', cue)`.

> **Semantic note**: the former wipe-all approach (clearing every event on the Track
> before rebuilding) was replaced with this selective overwrite after smoke testing
> showed it was destructive — a partial send (operator selects only some cues) would
> silently delete existing TC events for cues not in the send list.

`<seconds>` = SMPTE→seconds at 25 fps: `(HH * 3600) + (MM * 60) + SS + (FF / 25)`.

### Notes

- `rawtime` units are MA3's internal time, **not** SMPTE string and **not** seconds.
  Constant: `1 second = 16777216` (`= 2^24`).
- `Acquire()` semantics: on TimeRange / CmdSubTrack it returns the existing child
  if present, else creates one. On CmdSubTrack for Events, it always creates a
  new Event (so iterating `Acquire()` in a loop produces N distinct events).
- **Delete** (proven on a real desk 2026-06-06): it is `parent:Delete(1-basedChildIndex)`
  — a no-arg `child:Delete()` errors with "Wrong parameter #2". And **TimeRanges
  are structural**: `track:Delete(i)` on a TimeRange returns "deletion of the child
  object is prohibited". So clear events at the CmdSubTrack level (`sb:Delete(i)`),
  never delete TimeRanges. (`:Delete` is the property-API mutator, not the
  command-line `Delete` keyword.)
- The whole Lua command is one OSC packet per song; `sendCmdLinesViaOsc`'s
  throttle (20 ms) is mostly slack here.
- `buildTcLua` produces a paste-into-MA3 plugin that runs the **same** Object
  API hierarchy in a standalone `applySong(seq, cues)` function. Fallback path
  when OSC is unavailable.
- Older MA versions used `:Aquire()` (typo, no `c`). Current builds accept both.

## Timecode insert (Saetta iOS — overwrite, ticked cues)

Saetta reuses the **same Object API hierarchy** above (TrackGroup `Children()[1]`,
Track `tg[2]`, TimeRange, CmdSubTrack, Event) and **overwrites** the song's TC
track with the individually **ticked** cues — the web `buildTcCmdLines` proven
path. Each send wipes the track and rebuilds it, so re-sending a cue is never
duplicated.

`TimecodeBuilder.lines(song:ticked:)` emits **one** `Lua "<single-line code>"`
command per song carrying the ticked cues. The body runs inside `pcall(go)` and
`Printf`s a diagnostic at every exit point (which object was missing, the
TrackGroup child count when `tg[2]` is absent, TimeRanges wiped, events written,
runtime errors) to MA3's System Monitor — the only feedback channel available,
since the hub's OSC is send-only. Desk-side, `go()` does (single-quoted Lua
throughout — no double-quotes inside the `Lua "..."` wrapper):

1. **Resolve** `DataPool().sequences[N]` and `DataPool().timecodes[N]`. Bail if either missing.
2. **Locate** TrackGroup `t:Children()[1]` and Track `tg[2]`. Bail if either missing.
3. **Wipe** every TimeRange: `local trc=tr:Children()` then
   `for i=#trc,1,-1 do tr:Delete(i) end`. NOTE: `Delete` is
   `parent:Delete(1-basedChildIndex)` — calling `trc[i]:Delete()` (no-arg on the
   child) errors with "Wrong parameter #2" on the tested firmware. (The web
   `buildTcCmdLines` uses the no-arg child form; it only avoided the error because
   its proven run started on an empty track, so the wipe loop never executed.)
4. **Create** one fresh TimeRange `tr:Acquire()` and `CmdSubTrack`
   `rng:Acquire('CmdSubTrack')`.
5. **For each ticked cue**, ascending by `cue.n`: `e = sub:Acquire()` (a new
   Event), `e:Set('rawtime', <raw>)`, `cue = GetObject('Sequence N Cue c')`; if
   truthy, `e:Set('cuedestination', cue)`.

`<raw>` = `round(seconds * 16777216)`, `seconds` = SMPTE→seconds at 25 fps.

> **History note** — an append/upsert variant (skip the wipe; reuse the existing
> TimeRange/CmdSubTrack and replace only re-sent cues) was tried and abandoned on
> 2026-06-06: desk diagnostics showed `tr:Acquire()` creates a **new empty
> TimeRange every call** rather than returning the existing one, so prior events
> were never found and instead accumulated across orphan TimeRanges. Overwrite
> (matching the web path, all in one command) is the reliable model. Cost: cues
> not ticked in a given send are not on the track afterward — send the full set
> each time.
