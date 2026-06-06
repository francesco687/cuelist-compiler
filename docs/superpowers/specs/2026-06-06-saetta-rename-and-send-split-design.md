# Saetta — Rename + Send-Tab Split + Per-Cue Timecode Insert

**Status:** Ready for plan
**Date:** 2026-06-06
**Scope:** (1) Full rename of the iOS app `CuelistCompiler` → **Saetta**. (2) Split the Send tab's single "Send → MA" into three decoupled actions: **Send Cues**, **Send Notes**, **Send Timecode**. (3) New per-cue timecode insert: a tick box next to each cue's TC value; ticked cues get appended to the grandMA3 Timecode pool **without disturbing existing events**.

This is iOS-only. The hub, relay, desktop, and web apps are untouched. The shared `web/js/compile.js` and the `feature/timecode-per-cue` web branch are **not** merged or reused — TC is built natively in Swift (Approach A).

---

## Part 1 — Rename to Saetta

### Conventions (locked)

- App display name + product: **Saetta** (Italian for "lightning bolt" — fast cue dispatch).
- Xcode targets: `CuelistCompiler` → **`Saetta`**, `CuelistCompilerKit` → **`SaettaKit`**, `CuelistCompilerKitTests` → **`SaettaKitTests`**.
- Bundle ids: `com.blearred.saetta`, `com.blearred.saetta.kit`, `com.blearred.saetta.kittests`.
- Swift module: `import CuelistCompilerKit` → `import SaettaKit` (50 source/test files).
- Project file: regenerate `Saetta.xcodeproj` via xcodegen; delete the old `CuelistCompiler.xcodeproj`.
- Schemes renamed to `Saetta` / `SaettaKit`.
- `Info.plist`: `CFBundleName` → `Saetta`; add `CFBundleDisplayName` = `Saetta`; usage strings "Cuelist Compiler …" → "Saetta …".
- App entry type `CuelistCompilerApp` → `SaettaApp`.

### Consequence (accepted by user)

New bundle id ⇒ a **fresh install** on the iPhone (the old "CuelistCompiler" app stays until manually deleted) and a **one-time re-pair** with the hub/relay. This is a deliberate clean break, not a migration. No data-migration code is written; the project JSON on disk is unchanged (same schema), so a manual re-import or a fresh project is fine.

### Sequencing

The rename touches every Swift file's `import`. To keep the diff reviewable and the feature work clean, **do the rename first as its own commit(s)**, verify Kit tests + app build green under the new names, then layer the Send-split and TC features on top.

### Out of scope (rename)

- No App Store / TestFlight metadata, no icon redesign, no localization of the name.
- No automated migration of the old install's paired state.

---

## Part 2 — Split the Send tab into three buttons

### Today (entangled)

`SendView` has "Send → MA" (current song) and "Send All Songs". The compile path (run hub-side from `web/js/compile.js`, or natively) emits, per cue: the `Store Sequence N Cue n …` structure **with the note baked in** (`Set Sequence N Cue n "Note" "…"` right after each cue). Notes ride along with cues; there is no way to send one without the other, and no TC path at all.

### Target (decoupled)

Three independent buttons on the Send tab. Each is non-destructive to the others.

| Button | Emits | Scope selector |
|---|---|---|
| **Send Cues** | Sequence + cue structure (fade/delay/actions). **No `"Note"` lines.** | current / all (keep existing `.current` / `.all`) |
| **Send Notes** | Only `Set Sequence N Cue n "Note" "…"` for cues with a non-empty note | current / all |
| **Send Timecode** | Append-only TC events for **ticked** cues (Part 3) | current song only (TC is per-sequence; ticks are explicit) |

**Decision (locked): Send Cues no longer writes notes.** Notes are emitted only by Send Notes. This is a behavior change from the current entangled compile — called out so reviewers expect the `"Note"` lines to disappear from the cue-send output.

### How each button produces commands (Approach A — native Swift)

All three build their command lines **in `SaettaKit`** and send them via the hub as a sequence of raw `cmd` lines (`OutgoingMessage.cmd(line:)`), the same channel `sendCommand` already uses. This avoids any hub/relay change.

- **Send Cues** and **Send Notes** are two halves of the existing compile. We add a native Swift cue/notes command builder in the Kit (mirroring the documented contract in `shared/ma3-command-spec.md`), parameterized to emit cue-structure-only or notes-only. Progress/`done` feedback reuses the existing `hub.progress` / `hub.lastResult` plumbing where it sends a known line count; for raw-cmd batches we surface a simple sent-count.
- **Send Timecode** uses the TC builder in Part 3.

> Note on the existing `compile-send` path: the current "Send → MA" uses `OutgoingMessage.compileSend` (hub compiles). After this change, **Send Cues** becomes the cue-structure-only send. We may either (a) keep `compile-send` but have the hub stop emitting notes, or (b) build cue lines natively in Swift and send as raw cmds for symmetry with Notes/TC. **Plan decision: build all three natively in Swift and retire the iOS use of `compile-send`** — one consistent code path, no hub dependency, fully unit-testable. The hub keeps `compile-send` for the desktop/web; iOS just stops calling it. (If native cue-building proves heavier than expected during planning, fall back to option (a): a `notes: false` flag on `compile-send`. Recorded as the contingency.)

### Send-tab UI

Replace the two-button stack with a labeled three-action layout:

```
[ ● Connected / Tap to connect ]
Store mode: ( Overwrite | Merge )            ← unchanged, applies to Send Cues

Send Cues       [ current ]  [ all songs ]
Send Notes      [ current ]  [ all songs ]
Send Timecode   [ ticked cues → MA ]          ← current song; count of ticked cues shown
```

- Each row disabled+dimmed when offline (same as today).
- Send Timecode button label shows the ticked count, e.g. "Send Timecode (3 ticked)"; disabled when zero ticked.
- Result row (sent N lines / error) unchanged, shared across all three.

---

## Part 3 — Per-cue timecode insert (the core feature)

### User workflow (the real gig case)

> "Mid-show I find a cue is missing from the timecode track. I add the cue, type its SMPTE value, tick it, and Send Timecode. That one event lands in the MA timeline for the sequence. The other cues' timecodes are **never** touched."

### Data model

- Reuse the existing `Cue.position` field (`"HH:MM:SS:FF"`, already present, already populated from CuePoints import). No new persisted field for the value.
- **Tick state is transient session state, not persisted.** A `Set<Cue.ID>` (or `Set<UUID>`) of "selected for TC send" lives in `ProjectStore` (or a dedicated `TcSelection` observable), cleared on app launch and after a successful Send Timecode. Rationale: ticks represent "what I just added and want to push now"; persisting them risks stale, dangerous re-sends across launches. (Flagged for confirmation at spec review — if you'd rather the ticks persist with the project, it's a one-line model change + migration default `false`.)

### Per-cue UI (cue card)

Next to the TC value in each cue card:

```
[ TC: 00:00:47:16 ] [☐]      ← tick box; ticked = include in next Send Timecode
```

- Tick box only enabled when `position` is a **valid** SMPTE (`^\d{2}:\d{2}:\d{2}:\d{2}$`, `MM<60 SS<60 FF<25` at 25 fps). Invalid/empty TC ⇒ tick box disabled + greyed; can't be selected.
- Ticking toggles membership in the transient selection set.
- A small running count of ticked cues surfaces on the Send tab's Send Timecode button.

### MA3 contract — append-only insert (the #1 risk to verify)

**Conventions** (same as the web TC branch): TC pool number == Sequence number; 25 fps; `time` property is float seconds.

**Preconditions (operator, once per song on the desk):** Sequence N exists with cues; Timecode pool N exists; Track at `Timecode N.1.1` targets Sequence N. (Same manual setup the web spec documents; surfaced as a UI hint on the Send Timecode button.)

**The hard part:** an append must place the new event at the *next free index* of `Timecode N.1.1.1.1` **without** knowing the desk's current event count, and **without** the delete-all cleanup the web overwrite path uses. The web branch sidestepped this by rebuilding from empty (indices 1..n known) and concluded *merge is Lua-only*.

**Chosen mechanism (to prove on onPC): inline Lua merge command.** For each ticked cue, send a single raw `cmd` line that runs Lua on the desk. The Lua reads the pool's current event count, appends one event, and sets its `time` — all desk-side, so iOS never needs a read-back and the hub stays unchanged. Sketch (exact syntax/quoting to be verified on onPC):

```
Lua "local p=<N> local t=Timecode(p).Element(1).Element(1) local i=t.Count+1 Cmd('Store Timecode '..p..'.1.1.1.1 \"Goto Cue <c> Sequence '..p..'\" /NoConfirmation') Cmd('Set Timecode '..p..'.1.1.1.1.'..i..' Property \\'time\\' <secs>')"
```

- `<N>` = sequence number, `<c>` = cue number, `<secs>` = SMPTE→seconds float at 25 fps = `HH*3600 + MM*60 + SS + FF/25`.
- Events fire by **time**, not index order, so appending out of chronological order is fine.
- **Fallback if inline Lua proves too brittle to quote over OSC `/cmd`:** send a small **read-back** to learn the count (extend the existing pull/trigger mechanism — a "TC event count" probe analogous to `pull-sequences`), then emit plain `Store` + `Set …Property 'time'` cmd lines at `count+1`. This reintroduces a hub touch, so it's the contingency, not the default.

The Swift TC builder is unit-tested at the **string level** (given a cue + count/0-based assumptions, assert the exact command/Lua text), independent of whether a desk is present. Desk behavior (does the event land at the right time, are existing events preserved) is the **device-smoke gate**.

### Edge cases

| Case | Behavior |
|---|---|
| Cue with empty/invalid TC | Tick box disabled; can't be sent. |
| Zero cues ticked | Send Timecode button disabled. |
| Same cue ticked + already has a TC event on desk | Produces a duplicate event (two `Goto Cue X`). Acceptable for v1 (the feature targets *missing* cues); documented. No dedup. |
| Send Timecode while offline | Button disabled (same as other sends). |
| TC pool / Track not pre-created on desk | Events fail silently (MA3 doesn't ACK over OSC). UI reports "sent" without verifying — operator's responsibility per preconditions. Same caveat as all OSC sends. |
| Successful Send Timecode | Clear the tick selection. |

### Out of scope (TC, v1)

- Overwrite/rebuild-all mode (that's the web branch's job; explicitly not ported).
- Dedup against existing desk events; reading current desk TC state to diff.
- Capture-from-playhead 🎯 (the app has no audio playhead like web; TC is typed or imported).
- Frame rates ≠ 25 fps.
- Auto-creating the TC pool Track (operator drags manually, as in the web spec).
- Multi-fire (one cue → multiple TC values).

---

## Testing strategy

### Rename
- `xcodegen generate` → `xcodebuild` the `SaettaKit` scheme: **all Kit tests green** under new module name.
- App target builds. Bundle id / display name verified in built `Info.plist`.

### Send split (Swift unit tests in SaettaKit)
- Cue builder emits cue-structure lines and **no `"Note"` lines**.
- Notes builder emits only `Set … "Note"` lines, one per cue with a non-empty (sanitized) note, none for empty.
- Note sanitization (newline/tab/quote handling) ported with parity to the documented contract; golden-string test.

### Timecode builder (Swift unit tests)
- SMPTE→seconds conversion at 25 fps (incl. `00:00:00:00`, frame rollover boundaries).
- Valid/invalid SMPTE classification drives tick-box enablement.
- Builder produces the exact command/Lua text for a given ticked cue + sequence (golden string).
- Only ticked cues included; unticked/invalid excluded.

### UAT / device smoke (the gates that matter)
1. Rename: app installs as **Saetta**, re-pairs with hub/relay, sends a known song to onPC (regression of the existing flow under the new name).
2. Send Cues then Send Notes separately → cues land without notes, then notes populate.
3. On onPC: pre-create TC pool + Track per preconditions. Add a missing cue, type TC, tick it, Send Timecode → **the new event appears at the right time AND the previously-existing events are unchanged** (the core promise). Verify in the TC pool inspector.
4. Tick two cues, send → both land. Confirm tick selection clears after send.

---

## Implementation order (rough — for writing-plans)

1. **Rename** (project.yml, regenerate xcodeproj, 50 imports, Info.plist, app type) → build + Kit tests green. Commit.
2. **Native Swift command builders** in SaettaKit: cue-structure, notes, with unit tests. Wire **Send Cues** + **Send Notes** to raw-cmd sends; retire iOS `compile-send`.
3. **TC builder** in SaettaKit (SMPTE conv, validity, command/Lua text) with unit tests.
4. **Per-cue tick box** UI + transient selection state.
5. **Send tab** three-button layout + ticked-count + clear-on-send.
6. **onPC device smoke** — prove the append-only insert preserves existing events (resolve the Lua-vs-readback fork here).
7. Docs: update README + `shared/ma3-command-spec.md` with the iOS append-only TC section; CHANGELOG.

---

## Open questions for spec review

1. **Tick persistence:** transient (recommended, default above) vs. persisted-with-project? 
2. **Send Cues note removal:** confirmed full decouple — Send Cues emits zero note lines. (Locked; re-flagging because it changes existing send output.)
3. **TC mechanism fork** (inline Lua vs. read-back + plain cmds) is deliberately left to resolve at step 6 against a real onPC; the spec commits to *append-only, existing events preserved* as the invariant, not to the exact wire syntax.
