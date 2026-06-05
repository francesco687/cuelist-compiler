# Cue notes → grandMA3 cue Note column

**Date:** 2026-06-06
**Status:** Approved (design), pending implementation plan

## Problem

Each `Cue` already carries a `notes: String` field, populated on the iPhone via
the Notes mic / `NoteRouter` capture flow. Those notes ride along in the
`Project` JSON the iOS app sends to the hub (`compile-send`), but they are never
written to the lighting desk: `web/js/compile.js` — the single source of truth
the hub runs in a Node VM — reads only `cue.n/name/fade/delay/actions`. The note
is captured and assigned to the cue in the app, yet invisible on the grandMA3.

## Goal

On compile/send, write each cue's note into that cue's **Note property** (the
per-cue Note column in the Sequence Sheet) on the desk, so notes authored on the
iPhone appear in the actual cuelist.

## Behavior

After each cue is stored, if `cue.notes` is non-empty (after trimming), emit one
command setting the cue's Note property:

```
Set Sequence <seq> Cue <n> "Note" "<sanitized note>"
```

It is placed immediately after the existing `Store …` line for that cue,
alongside the existing `Set … Fade` / `Set … Delay` lines, and follows the same
conditional shape (emit only when the value is present).

- **Empty / whitespace-only notes emit nothing.** No Note command is sent, which
  leaves the desk's existing Note field untouched (we do not actively clear it).
- **Sanitization.** Notes are voice-captured and may contain quotes or newlines.
  Escape `"` → `\"`, collapse any run of newlines/tabs/whitespace to a single
  space, then trim. The result is always a single valid command line.

## Scope

**In scope — one file is the source of truth:** `web/js/compile.js`
- `buildCmdLines()` — the live-OSC path the hub runs for the iPhone send.
- `buildLua()` / `songToLuaEntry()` — the exported `.lua` plugin, kept identical
  per the in-file contract that both must emit the same sequence.
- `shared/ma3-command-spec.md` — documented in the same change, per the header
  rule ("any change to the sequence updates this file **and** `compile.js` in the
  same PR").

**Out of scope**
- No iOS UI change. The `notes` field, capture flow, and `Project` JSON transport
  already exist and already carry the note to the hub.
- No web frontend notes field. The web UI has no notes input today; this change
  only makes the *existing* iPhone-authored notes reach the desk. `compile.js`
  simply emits the note when present, so a future web notes field would work for
  free.

## Testing

`compile.js` is covered by a golden-file test through the hub VM bridge
(`hub/test/compile-bridge.test.js`, run via `node --test` in `hub/`), comparing
`compileShow()` output against `examples/SONG_1.cmdlines.txt` from
`examples/SONG_1.json`.

- Add a focused test: a cue with a `notes` value produces the expected
  `Set Sequence … Cue … "Note" "…"` line in the right position; a cue with an
  empty note produces no Note line; sanitization (quotes/newlines) is asserted.
- Update the `SONG_1` golden fixture + expected lines if a note is added to it
  (or keep the golden note-free and assert notes in a separate focused fixture).

## Verify on hardware

The exact grandMA3 property keyword for the cue Note column. `Set Sequence X
Cue Y "Note" "…"` is the expected syntax (it mirrors how `Fade`/`Delay` are set
right after `Store`). If the desk spells the property differently (e.g.
`CueNote`), it is a one-token fix in the same location. Confirm during the next
desk smoke test.
