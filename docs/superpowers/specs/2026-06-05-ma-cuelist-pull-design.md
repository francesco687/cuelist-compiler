# Pull-and-edit a live MA sequence — design

**Date:** 2026-06-05
**Status:** Draft for review
**Branch (work happens on):** off `main`

## Problem

The current authoring flow is one-way and forward-only:

```
CuePoints (markers on audio) → exported cuelist on grandMA3 → filled with lighting
```

Once a cuelist lands on the MA there is no path back to CuePoints. But the real
need on the desk is **iteration on cues that already exist on MA** — and
occasionally adding new ones. Today the iPhone app can only author *new* content
and push it out; it cannot see or edit what is already stored on a sequence.

## Goal

From the iPhone, **one-tap pull** a chosen MA sequence's cues down into the app as
an editable song, edit it (manually or by voice — including per-group preset
content), and **push edits back live** to that same sequence:

- edits/adds → Store with **Merge**
- deletes → real `Delete Cue` on MA, **confirm-gated**

The headline interaction is voice on a pulled cuelist, e.g.:

> "On the group WASH FLOOR change the colour to red instead of green, and change
> the position fade to 5 seconds."

This is expressible in the existing model: an action carries a `group` plus a
preset per pool, and each `Preset` already has its own `fade`/`delay`.

## Non-goals (v1)

- Two-way live *sync* (no background reconciliation; pull is an explicit action).
- Conflict resolution against desk-side edits made after a pull (see Risks).
- Reading raw attribute *values* that were not stored as presets (we read the
  group→preset recipe, not arbitrary hard values). Fidelity confirmed by spike.
- Pulling more than one sequence into a single song; each pull = one song.
- A 30s recording cap (separate deferred item).

## Decisions (locked during brainstorming)

| Question | Decision |
|----------|----------|
| Read depth | **Skeleton + group list + per-group feature presets + timing** (cue-level fade/delay and per-preset fade/delay). |
| Pull transport | **One-tap live pull via a network-share file the hub watches** (Approach A). Spike-gated; fallback to guided transfer (Approach C) if the share/trigger path fails. |
| Pull target | **New "pulled" song bound to the sequence number.** Other songs stay. |
| Push-back | **Merge** for edits/adds; **real deletes, confirm-gated**, enumerated before firing. |
| Voice | Reuses the existing voice-authoring pipeline unchanged once the pulled song is the active document. |

## The pull contract (frozen)

A new versioned contract document in `shared/` (sibling to `ma3-command-spec.md`),
shared by the plugin, the hub, and iOS. It is a **subset of the song JSON shape**,
dropping UI-only fields (`id`, `color` tag, `collapsed`, `position` label).

```jsonc
{
  "version": 1,
  "sequence": 666,
  "cues": [
    {
      "no": 1.0,                         // Double — MA cue number
      "name": "Verse",
      "fade": "3",                       // cue-level fade (string, fidelity matters)
      "delay": "",
      "actions": [
        {
          "group": "WASH FLOOR",
          "presets": {
            "color":    { "name": "Green", "fade": "",  "delay": "" },
            "position": { "name": "Stage", "fade": "3", "delay": "" },
            "dimmer":   { "name": "",      "fade": "",  "delay": "" },
            "gobo":     { "name": "",      "fade": "",  "delay": "" },
            "beam":     { "name": "",      "fade": "",  "delay": "" },
            "focus":    { "name": "",      "fade": "",  "delay": "" }
          }
        }
      ]
    }
  ],
  "error": null                          // non-null string when the dump failed (e.g. "sequence 666 not found")
}
```

Pool keys are the six `Pool` raw values (`color, dimmer, position, gobo, beam,
focus`). Strings are preserved verbatim (the compiler trims/empty-checks
downstream, so `"3"` vs `"3.0"` fidelity matters). An empty preset = `name: ""`.

## Architecture

```
iPhone ──pullSequence{seqNo}──▶ Hub ──OSC /cmd "Plugin …"──▶ MA3
  ▲                              │                            │
  │                              │   dump_sequence.lua writes │
  │   pulledCuelist{…}           ▼   JSON to share folder ◀───┘
  └──────────────────────── Hub watches folder, parses, relays
```

### 1. MA3 plugin — `plugins/dump_sequence.lua`

Sibling to `export_pools.lua`, same proven serialization pattern (walk object
model → build JSON string → write file, with a print-to-monitor fallback).

- **Input:** a sequence number. The hub sets it before invoking (e.g. via a
  user-var) so the run is unattended; a manual run still prompts via a dialog
  (mirrors `export_pools` `DEFAULT_*`).
- **Walk:** `DataPool().Sequences[seqNo]` → its cue pool → each cue:
  `no`, `name`, cue-level `fade`/`delay`, then each part's recipe lines →
  `group` + the referenced preset per feature pool + per-preset `fade`/`delay`.
- **Output:** JSON (matching the pull contract) to a configured share path
  (primary); print-to-monitor between `=== CUELIST_PULL_BEGIN/END ===` markers
  (fallback, reused by guided transfer).
- **Errors:** sequence not found / unreadable → emit `{"error": "...", "cues": []}`.

> **Unproven:** reading `group → preset` faithfully out of a cue's recipe. The
> spike (Milestone 1) validates this on a real desk before anything else is built.

### 2. Hub additions

New WebSocket messages (added to the frozen hub-WS protocol, port 9000):

- `pullSequence { seqNo }` (iPhone → hub)
- `pulledCuelist { sequence, cues, error }` (hub → iPhone)
- `pullError { message }` (hub → iPhone) — transport/timeout failures distinct
  from MA-side `error` carried inside `pulledCuelist`.

On `pullSequence` the hub:
1. sets the target seq for the plugin and fires an OSC `/cmd` to run it
   (`Plugin "dump_sequence"` — the existing `/cmd` channel, no new transport),
2. watches the configured share folder for the JSON (debounced, with a timeout),
3. parses, validates against the contract, relays as `pulledCuelist`,
4. on timeout / parse failure → `pullError`.

Config: hub-side share-folder path + the plugin name. Documented in README and
fixed by the spike.

### 3. iPhone additions

- **Pull entry point:** a "Pull from MA…" action (toolbar menu) that asks for a
  sequence number, sends `pullSequence` via the existing `HubClient`, and shows
  progress (reuse the voice-style phase affordance).
- **On `pulledCuelist`:** map JSON → a **new `Song`** with `sequence = seqNo` and
  `sourceSequence = seqNo` set, appended to the project and made active. If
  `error` is non-null, surface it non-destructively and change nothing.
- **Editing:** reuses `CueListView` and the **existing voice pipeline unchanged**
  — once the pulled song is active, "WASH FLOOR colour red, position fade 5s"
  flows through the current `CommandInterpreter` → `ShowEdit` → `ShowEditApplier`.
- **Pull snapshot:** the song retains the original pulled cue numbers so push-back
  can diff for deletions.

### 4. Model changes (additive, decode-safe)

`Song` gains:

- `sourceSequence: Int?` — non-nil marks a pulled song bound to that MA sequence.
- `pulledSnapshot: [Double]?` — original cue numbers at pull time (for delete diff).

Both decoded with the existing `decodeIfPresent` pattern, so old projects load
unchanged and `Migration.swift` needs no destructive change. Non-pulled songs
leave both nil and behave exactly as today.

### 5. Push-back (live write to the bound sequence)

When sending a pulled song:

- Edited/added cues → Store with **Merge** (only touched attributes change),
  using the compiler's existing command generation + Merge/Overwrite machinery.
- Cues present in `pulledSnapshot` but absent now → `Delete Cue <seq> cue/<n>`.
- **Confirm dialog enumerates every Store and Delete command before anything
  fires.** Nothing is sent until the user confirms. This is the only destructive
  path and it is gated.

## Spike first — gates the whole feature (Milestone 1)

On the real grandMA3 desk, before building the app/hub surface:

1. Minimal `dump_sequence.lua` reads a known sequence → group→preset → timing →
   JSON to a folder the Mac mounts as a share.
2. Confirm the Mac hub can read that file.
3. Confirm the hub can trigger the plugin via OSC `/cmd` (`Plugin …`).
4. Confirm **group→preset fidelity** against what's actually stored.

**Outcome decides transport:**
- Pass → proceed with Approach A (one-tap live pull).
- Fail (no writable shared path, or `/cmd` can't trigger the plugin) → fall back
  to **Approach C (guided transfer):** user runs the plugin, AirDrops/pastes the
  JSON into the app. Editing + push-back are byte-for-byte identical either way,
  so only the pull entry point changes.

## Error handling

| Failure | Behaviour |
|---------|-----------|
| Pull timeout (file never appears) | `pullError` → "Couldn't reach MA — is the plugin installed and the share mounted?" Current state untouched. |
| Malformed / partial JSON | Rejected; current state untouched. |
| Sequence not found on MA | `pulledCuelist.error` surfaced; nothing loaded. |
| Push confirm cancelled | No commands sent. |

## Testing

- **Kit:** pull-contract decode (golden JSON → `Song` with `sourceSequence`,
  actions, per-preset timing); delete-diff (snapshot vs edited → correct delete
  set); push command-gen for a pulled song (Merge stores + Delete commands).
  Extend existing `ShowEditApplier*` / command-gen tests.
- **Hub:** `pullSequence` round-trip; folder-watch happy path + timeout (temp dir).
- **Plugin:** not CI-testable; validated by the spike + device smoke.
- **Device smoke:** pull a real sequence → voice-edit ("WASH FLOOR colour red,
  position fade 5 s") → push back with confirm → verify on the desk.

## Risks

- **Read fidelity (highest):** cues not stored as presets may not yield a clean
  group→preset recipe. Spike-gated; guided-transfer fallback does not remove this
  risk (same plugin read), so the spike is the true go/no-go.
- **Desk-side edits after a pull:** v1 has no reconciliation; Merge limits blast
  radius and deletes are confirm-gated, but a stale pull can re-Store old values.
  Acceptable for a single-operator workflow; revisit if multi-op.
- **Share writability on a hardware desk:** may differ from onPC. Spike confirms.

## Milestones

1. **Spike** — prove read + trigger + share + fidelity on the real desk (go/no-go).
2. **Contract** — freeze `shared/` pull contract + `dump_sequence.lua` to spec.
3. **Hub** — pull messages, plugin trigger, folder-watch, timeout, validation.
4. **iOS pull** — entry point, map JSON → pulled `Song`, model fields, snapshot.
5. **iOS push-back** — Merge stores + confirm-gated deletes from snapshot diff.
6. **Voice on pulled songs** — verify the existing pipeline covers the headline
   edit; close any vocabulary gaps.
7. **Device smoke** — end-to-end on the desk.
