# MA Cuelist Pull — Phase 0 Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **This is a SPIKE, not a TDD feature plan.** It is exploratory hardware work. There is no CI for grandMA3 Lua, so validation is by *observation on the real desk*, not by automated asserts. The deliverable is **knowledge + a go/no-go**, captured in a findings doc — plus a throwaway-but-reusable probe plugin and two small hub tools. Do not over-engineer; the point is to learn what a real cue exposes.

**Goal:** Prove on a real grandMA3 desk that we can read a sequence's cues at group→preset depth into JSON, land that JSON where the Mac hub can read it, and trigger the whole thing over OSC `/cmd` — then capture exactly what's readable so the pull contract can be finalized.

**Architecture:** A probe Lua plugin (`dump_sequence.lua`) walks the MA object model for one sequence and writes JSON to a file (plus a structural probe dump to the System Monitor). A standalone hub watcher reads that file from a Mac-mounted share. A standalone hub trigger fires `Plugin "dump_sequence"` over the existing OSC `/cmd` channel. Findings feed the contract.

**Tech Stack:** grandMA3 Lua plugin API; Node.js (hub, `fs.watch`, existing `OscSender`); SMB share between desk and Mac.

**Spec:** `docs/superpowers/specs/2026-06-05-ma-cuelist-pull-design.md` (Milestone 1).

---

## What this spike must answer (the go/no-go checklist)

By the end, the findings doc must state, with evidence:

1. **Read fidelity** — for a cue stored the way this project stores cues, can we read, per cue: `no`, `name`, cue-level fade/delay, and per part the **group name + the referenced preset per feature pool + per-preset fade/delay**? Which of these are readable, which are not?
2. **Object-model paths** — the actual property/child paths that worked (so the real plugin isn't guesswork).
3. **Share transport** — can the desk write the JSON to a folder the Mac mounts, and can the hub read it?
4. **OSC trigger** — can the hub trigger the plugin unattended via `/cmd`, and pass it a target sequence number?
5. **Verdict** — Approach A (one-tap live pull) viable, or fall back to Approach C (guided transfer)? Plus any contract refinements.

---

## File Structure

- Create: `plugins/dump_sequence.lua` — probe + best-effort JSON dump for one sequence.
- Create: `hub/tools/spike_pull_watch.js` — standalone folder watcher; reads + validates the JSON, prints a summary.
- Create: `hub/tools/spike_pull_trigger.js` — standalone OSC trigger; sends `Plugin "dump_sequence"` (optionally setting a target-seq user var first).
- Create: `docs/superpowers/spikes/2026-06-05-ma-cuelist-pull-findings.md` — the deliverable.

No changes to shipped hub `src/` or to iOS in this spike. The two hub tools live under `hub/tools/` and import the existing `src/osc.js`.

---

## Task 1: Probe plugin — `dump_sequence.lua`

**Files:**
- Create: `plugins/dump_sequence.lua`

This is a *probe*: it (a) dumps the structure of the target sequence's cues to the System Monitor so we can SEE what's readable, and (b) makes a best-effort attempt at the structured JSON contract. It is defensive (pcall everything, try multiple property names), modelled on `plugins/export_pools.lua`.

- [ ] **Step 1: Write the probe plugin**

```lua
-- Cuelist Compiler — Sequence Dumper (SPIKE PROBE)
-- Reads ONE sequence's cues and (a) prints a structural probe to the System
-- Monitor, (b) writes best-effort JSON (the pull contract) to OUT_PATH.
-- Defensive on purpose: we do not yet know the exact object-model paths — that
-- is what this spike is for. Modelled on export_pools.lua.

-- ── Config (edit for a manual run; the hub trigger overrides SEQ via user var) ──
local OUT_PATH    = "/Users/Shared/cuelist-pull/seq.json"  -- a Mac-mounted share path on the desk
local DEFAULT_SEQ = 666                                     -- target sequence number
local MAX_CUES    = 200                                     -- safety cap
local PROBE_DEPTH = 3                                       -- how deep to walk children when probing

-- ── Helpers (mirrors export_pools.lua style) ───────────────────────────────────
local function tryGet(t, key)
  if t == nil then return nil end
  local ok, v = pcall(function() return t[key] end)
  if ok then return v end
  return nil
end

local function tryCall(obj, method, ...)
  if obj == nil then return nil end
  local args = { ... }
  local ok, v = pcall(function() return obj[method](obj, table.unpack(args)) end)
  if ok then return v end
  return nil
end

local function escape(s)
  if s == nil then return "" end
  return tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"')
end

-- Read the target sequence number from a user variable if set (hub trigger path),
-- else DEFAULT_SEQ. We try a few API shapes since this is unconfirmed.
local function targetSeq()
  local attempts = {
    function() return tonumber(GetVar(UserVars(), "pullseq")) end,
    function() return tonumber(GetVar(GlobalVars(), "pullseq")) end,
  }
  for _, fn in ipairs(attempts) do
    local ok, v = pcall(fn)
    if ok and v then return v end
  end
  return DEFAULT_SEQ
end

local function findDataPool()
  local R = Root()
  local sd  = tryGet(R, "ShowData")
  local dps = tryGet(sd, "DataPools")
  local dp  = tryGet(dps, "Default") or tryGet(dps, 1)
  return dp
end

local function findSequence(dp, no)
  local seqs = tryGet(dp, "Sequences")
  if seqs == nil then return nil end
  return tryGet(seqs, no) or tryGet(seqs, tostring(no))
end

-- Iterate an object's children across the API shapes MA3 might expose.
local function childrenOf(obj)
  local kids = tryCall(obj, "Children")
  if type(kids) == "table" then return kids end
  local count = tryCall(obj, "Count") or tryGet(obj, "count")
  if type(count) == "number" then
    local out = {}
    for i = 1, count do out[#out + 1] = tryGet(obj, i) end
    return out
  end
  return {}
end

-- ── Probe: print everything readable about the sequence's cues ──────────────────
local PROP_GUESSES = {
  "name", "no", "number", "index",
  "CueFade", "Fade", "fade", "CueDelay", "Delay", "delay",
  "object", "Object", "TargetObject", "Group", "group",
  "preset", "Preset", "value", "Value", "Cue",
}

local function probeObj(label, obj, depth)
  if obj == nil or depth < 0 then return end
  local line = "[probe] " .. label .. " {"
  for _, k in ipairs(PROP_GUESSES) do
    local v = tryGet(obj, k)
    if v ~= nil and type(v) ~= "table" and type(v) ~= "userdata" then
      line = line .. string.format(' %s=%q', k, tostring(v))
    end
  end
  line = line .. " }"
  Printf(line)
  if depth > 0 then
    local kids = childrenOf(obj)
    for i, kid in ipairs(kids) do
      probeObj(label .. "/" .. i, kid, depth - 1)
    end
  end
end

-- ── Best-effort structured extraction (the pull-contract shape) ─────────────────
-- These property names are GUESSES; the probe output tells us the real ones, and
-- we refine in a later iteration of this same spike.
local POOL_KEYS = { "color", "dimmer", "position", "gobo", "beam", "focus" }

local function emptyPresets()
  local parts = {}
  for _, k in ipairs(POOL_KEYS) do
    parts[#parts + 1] = string.format('"%s":{"name":"","fade":"","delay":""}', k)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function cueToJson(cue)
  local no    = tryGet(cue, "no") or tryGet(cue, "number") or 0
  local name  = tryGet(cue, "name") or ""
  local fade  = tryGet(cue, "CueFade") or tryGet(cue, "Fade") or ""
  local delay = tryGet(cue, "CueDelay") or tryGet(cue, "Delay") or ""
  -- Actions left empty in the probe; the probe dump shows us where group/preset
  -- live so the next iteration fills `actions` for real.
  return string.format(
    '{"no":%s,"name":"%s","fade":"%s","delay":"%s","actions":[]}',
    tostring(tonumber(no) or 0), escape(name), escape(tostring(fade)), escape(tostring(delay)))
end

-- ── Write JSON to a file, fallback to monitor ───────────────────────────────────
local function writeFile(path, text)
  local f = io.open(path, "w")
  if f == nil then return false end
  f:write(text); f:close()
  return true
end

-- ── Main ────────────────────────────────────────────────────────────────────────
return function()
  local seqNo = targetSeq()
  local dp = findDataPool()
  if dp == nil then Printf("[dump_sequence] ERROR: no DataPool"); return end
  local seq = findSequence(dp, seqNo)
  if seq == nil then
    local err = string.format('{"version":1,"sequence":%d,"cues":[],"error":"sequence %d not found"}', seqNo, seqNo)
    writeFile(OUT_PATH, err)
    Printf("[dump_sequence] sequence " .. seqNo .. " not found")
    return
  end

  Printf("=== CUELIST_PULL_PROBE_BEGIN seq=" .. seqNo .. " ===")
  probeObj("seq", seq, PROBE_DEPTH)
  Printf("=== CUELIST_PULL_PROBE_END ===")

  local cues = childrenOf(seq)
  local jsonCues = {}
  for i, cue in ipairs(cues) do
    if i > MAX_CUES then break end
    jsonCues[#jsonCues + 1] = cueToJson(cue)
  end
  local json = string.format(
    '{"version":1,"sequence":%d,"cues":[%s],"error":null}',
    seqNo, table.concat(jsonCues, ","))

  local wrote = writeFile(OUT_PATH, json)
  Printf("=== CUELIST_PULL_BEGIN ===")
  Printf(json)
  Printf("=== CUELIST_PULL_END ===")
  Printf(string.format("[dump_sequence] seq=%d cues=%d wroteFile=%s path=%s",
    seqNo, #jsonCues, tostring(wrote), OUT_PATH))
end
```

- [ ] **Step 2: Commit**

```bash
git add plugins/dump_sequence.lua
git commit -m "spike(plugins): probe dump_sequence.lua — structural probe + best-effort cuelist JSON"
```

> **Note:** `io.open` may be unavailable in the MA3 Lua sandbox. If file write fails (`wroteFile=false`), that is a *finding* — the monitor block between `CUELIST_PULL_BEGIN/END` is the fallback, and the share transport may need MA's own `Export`. Record it in Task 7.

---

## Task 2: Hub watcher — `spike_pull_watch.js`

**Files:**
- Create: `hub/tools/spike_pull_watch.js`

Standalone Node script: watch a folder for the JSON file, read it, JSON-parse, validate it loosely against the contract, and print a summary. This proves the Mac hub can read what the desk wrote.

- [ ] **Step 1: Write the watcher**

```js
'use strict';
// SPIKE: watch a folder for the cuelist-pull JSON the desk plugin writes,
// parse it, and print a summary. Usage:
//   node hub/tools/spike_pull_watch.js /Users/Shared/cuelist-pull/seq.json
const fs = require('node:fs');
const path = require('node:path');

const target = process.argv[2] || '/Users/Shared/cuelist-pull/seq.json';
const dir = path.dirname(target);
const base = path.basename(target);

function summarize(file) {
  let raw;
  try { raw = fs.readFileSync(file, 'utf8'); }
  catch (e) { console.log('[watch] read failed:', e.message); return; }
  let obj;
  try { obj = JSON.parse(raw); }
  catch (e) { console.log('[watch] JSON parse failed:', e.message, '\n--- raw ---\n', raw); return; }
  console.log('[watch] parsed OK:',
    'version=', obj.version,
    'sequence=', obj.sequence,
    'cues=', Array.isArray(obj.cues) ? obj.cues.length : '(none)',
    'error=', obj.error);
  if (Array.isArray(obj.cues) && obj.cues.length) {
    const c = obj.cues[0];
    console.log('[watch] first cue:', JSON.stringify(c, null, 2));
  }
}

console.log('[watch] watching', dir, 'for', base);
if (fs.existsSync(target)) summarize(target);
fs.watch(dir, (event, filename) => {
  if (filename === base) {
    // debounce: writes can fire multiple events
    setTimeout(() => summarize(target), 150);
  }
});
```

- [ ] **Step 2: Smoke it locally (no desk needed)**

Run, then in another shell write a fake file to confirm the watcher fires:

```bash
mkdir -p /Users/Shared/cuelist-pull
node hub/tools/spike_pull_watch.js /Users/Shared/cuelist-pull/seq.json &
printf '{"version":1,"sequence":666,"cues":[{"no":1,"name":"Verse","fade":"3","delay":"","actions":[]}],"error":null}' > /Users/Shared/cuelist-pull/seq.json
```

Expected: watcher prints `parsed OK: version= 1 sequence= 666 cues= 1` and the first cue.

- [ ] **Step 3: Commit**

```bash
git add hub/tools/spike_pull_watch.js
git commit -m "spike(hub): standalone folder watcher for cuelist-pull JSON"
```

---

## Task 3: Hub trigger — `spike_pull_trigger.js`

**Files:**
- Create: `hub/tools/spike_pull_trigger.js`

Standalone Node script using the existing `OscSender` to fire the plugin over `/cmd`. First sets a target-sequence user var, then runs the plugin. This proves the unattended trigger path and the seq-param mechanism.

- [ ] **Step 1: Write the trigger**

```js
'use strict';
// SPIKE: trigger dump_sequence.lua on the desk over OSC /cmd. Usage:
//   node hub/tools/spike_pull_trigger.js 666 [ma3Host] [ma3Port] [prefix]
const { OscSender } = require('../src/osc.js');

const seq = parseInt(process.argv[2] || '666', 10);
const host = process.argv[3] || '127.0.0.1';
const port = parseInt(process.argv[4] || '8000', 10);
const prefix = process.argv[5] || 'gma3';

const sender = new OscSender({ host, port, prefix });

async function main() {
  // Set the target sequence as a user var, then run the plugin by name.
  // Both lines go through /gma3/cmd. If user vars don't survive, the plugin
  // falls back to its own DEFAULT_SEQ — recorded as a finding.
  await sender.send(`SetUserVariable "pullseq" "${seq}"`);
  await sender.send(`Plugin "dump_sequence"`);
  console.log(`[trigger] sent SetUserVariable pullseq=${seq} + Plugin "dump_sequence" to ${host}:${port} /${prefix}/cmd`);
  sender.close();
}
main().catch((e) => { console.error('[trigger] failed:', e); process.exit(1); });
```

- [ ] **Step 2: Smoke the encoding locally (no desk)**

Confirm it sends without throwing (a UDP packet to a dead port is fine — we only check it doesn't crash and the address/encoding is valid):

```bash
node hub/tools/spike_pull_trigger.js 666 127.0.0.1 8000 gma3
```

Expected: prints `[trigger] sent SetUserVariable pullseq=666 + Plugin "dump_sequence" ...`, exits 0.

- [ ] **Step 3: Commit**

```bash
git add hub/tools/spike_pull_trigger.js
git commit -m "spike(hub): standalone OSC trigger for dump_sequence plugin"
```

> **Note:** `SetUserVariable` exact syntax is unconfirmed for `/cmd`. If the user var doesn't reach the plugin, alternatives to try on the desk: `SetGlobalVariable`, or encode the seq into the plugin name/argument. Record what worked in Task 7.

---

## Task 4: Desk run — manual fidelity check (THE spike)

**Files:** none (desk procedure + observations recorded in Task 7).

This is the heart of the spike. Pick a sequence on the real desk that was authored the way this project authors cues (Group + presets via the compiler), and run the plugin **manually first** (not via OSC) to read the probe output.

- [ ] **Step 1: Install the plugin on the desk**

Import `plugins/dump_sequence.lua` into a plugin slot (same way `export_pools.lua` is used — see `README.md`). Open the System Monitor (so probe output is visible).

- [ ] **Step 2: Point it at a real sequence**

Edit the plugin's `DEFAULT_SEQ` to a known, fully-authored sequence number on this show, and `OUT_PATH` to a writable local path first (e.g. a USB or local folder), to isolate "can we read" from "can we share".

- [ ] **Step 3: Run it manually and read the probe**

Run the plugin. In the System Monitor, read the block between `CUELIST_PULL_PROBE_BEGIN` and `CUELIST_PULL_PROBE_END`.

Record (for Task 7): for the sequence, the cues' children, and within each cue the parts and recipe/cuedata lines — **which printed properties carry the group name and the referenced preset per feature pool**, and the cue/preset fade/delay. Note the exact property names and child nesting that worked.

- [ ] **Step 4: Fidelity verdict for depth**

Against what is actually stored in one known cue (eyeball it on the desk), decide:
- ✅ readable: cue no, name, cue fade/delay
- ❓ group name per part — readable? via which property?
- ❓ preset reference per feature pool — readable, or only raw values? via which property?
- ❓ per-preset fade/delay — readable?

This verdict is the go/no-go on the **depth** (spec Decision: skeleton + group list + per-group presets). If presets aren't recoverable but groups are, that's a contract narrowing to record, not a failure.

---

## Task 5: Share transport check

**Files:** none (desk + Mac procedure, recorded in Task 7).

- [ ] **Step 1: Mount a share both machines see**

On the Mac, share a folder (or mount an SMB share both the desk and Mac reach). Confirm the desk can see/write it (the desk OS exposes network locations; if not, USB-relay is the fallback and a finding).

- [ ] **Step 2: Point the plugin's `OUT_PATH` at the share and run**

Set `OUT_PATH` to the share path, run the plugin manually. Confirm a `seq.json` appears.

- [ ] **Step 3: Read it from the Mac hub**

```bash
node hub/tools/spike_pull_watch.js <share>/seq.json
# then re-run the plugin on the desk; watcher should print "parsed OK"
```

Expected: watcher prints `parsed OK ... cues= N`. If `wroteFile=false` on the desk (sandbox blocks `io.open`), record it — fallback is MA's native `Export` to the share, or guided transfer (Approach C).

---

## Task 6: OSC trigger check (unattended)

**Files:** none (desk + Mac procedure, recorded in Task 7).

- [ ] **Step 1: Configure MA OSC input** per `README.md` ("OSC live mode": Enable Input, Echo Input=Yes, port 8000, prefix gma3) — same config the live-send already needs.

- [ ] **Step 2: Trigger from the Mac**

```bash
node hub/tools/spike_pull_trigger.js <known-seq> <ma3-host> 8000 gma3
```

- [ ] **Step 2b: Watch in parallel**

In another shell: `node hub/tools/spike_pull_watch.js <share>/seq.json`

Expected: the trigger causes the plugin to run on the desk, write the share file, and the watcher prints `parsed OK` for the sequence passed on the command line (proving the seq param crossed too).

- [ ] **Step 3: Record** whether `SetUserVariable` carried the seq, or a fallback was needed.

---

## Task 7: Findings + verdict (the deliverable)

**Files:**
- Create: `docs/superpowers/spikes/2026-06-05-ma-cuelist-pull-findings.md`

- [ ] **Step 1: Write the findings doc**

Fill in, with evidence from Tasks 4–6:

```markdown
# MA Cuelist Pull — Spike Findings (2026-06-05)

## 1. Read fidelity (Task 4)
- Object-model paths that worked: DataPool=`...`, Sequence=`...`, cues=`...`, parts=`...`, recipe lines=`...`
- Readable per cue: no [y/n], name [y/n], cue fade [y/n], cue delay [y/n]
- Group name per part: [y/n] via property `...`
- Preset reference per pool: [y/n] via property `...` (or only raw values: [y/n])
- Per-preset fade/delay: [y/n] via property `...`
- **Depth verdict:** full group→preset / groups-only / skeleton-only

## 2. Share transport (Task 5)
- io.open file write from plugin: [works / blocked]
- Share both machines see: [smb / usb-relay / none]
- Hub read of the file: [works / no]

## 3. OSC trigger (Task 6)
- Plugin runs via `Plugin "dump_sequence"` over /cmd: [y/n]
- Seq param via SetUserVariable: [y/n], fallback used: `...`

## 4. VERDICT
- [ ] Approach A (one-tap live pull) viable
- [ ] Fall back to Approach C (guided transfer)
- Contract refinements for the full plan: `...`
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/spikes/2026-06-05-ma-cuelist-pull-findings.md
git commit -m "spike(docs): MA cuelist pull findings + go/no-go verdict"
```

- [ ] **Step 3: Hand back**

Report the verdict. If Approach A is viable, the next step is to write the **full Phases 1–5 plan** against the (possibly refined) contract. If only Approach C, the full plan keeps every downstream phase and swaps just the pull entry point.

---

## Self-review notes

- **Spec coverage:** This plan covers spec Milestone 1 only (the gate). Phases 1–5 are deliberately deferred until the findings refine the contract — per the agreed "spike plan now, full plan after".
- **Not TDD:** intentional — Lua-on-hardware has no CI. The two hub tools (Tasks 2–3) have local smoke checks that don't need the desk; the plugin (Task 1) and Tasks 4–6 are validated by observation, which is the correct posture for a spike.
- **Throwaway-but-useful:** `dump_sequence.lua` is a probe; the real plugin in Phase 2 is rewritten against the confirmed paths. `spike_pull_*.js` tools may graduate into hub `src/` later but are not load-bearing yet.
