# Cue Inclusion Flags + Left Trim Handle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-cue `includeStore` and `includeTc` toggle chips so exports/sends can skip individual cues, and restore a left trim handle on the audio timeline (symmetric to the existing right end handle).

**Architecture:** Data model changes in `state.js`. Single-point filtering in `compile.js` (sole source of truth for both `.lua` and OSC paths). Chip UI in `render.js` + Amber-HUD CSS tokens. Left handle is a new DOM element + drag handler in `audio.js` mirroring the end handle pattern, sharing the existing `.trim-handle` CSS class.

**Tech Stack:** Vanilla JS (no framework), Node `--test` runner, CSS variables for Amber HUD tokens.

**Spec:** `docs/superpowers/specs/2026-06-12-cue-inclusion-flags-and-left-trim-handle-design.md`

**Branch:** `feat/cue-inclusion-flags-and-left-trim-handle` (off `origin/main` `36de1da`)

---

## Task 1: Data model — `includeStore`/`includeTc` defaults + migration

**Files:**
- Modify: `web/js/state.js` (functions `newCue` around line 27, `appendCueWithTcAndResort` around line 40, `migrateCues` around line 93)
- Modify: `web/js/state.js` (csv import path around line 509)
- Modify: `web/test/tc.test.js` (add migration test) **or** create: `web/test/state.test.js`

We add a dedicated test file `web/test/state.test.js` for the migration behaviour since `tc.test.js` is focused on TC emission. Keeps test files focused.

- [ ] **Step 1: Write the failing migration test**

Create `web/test/state.test.js`:

```javascript
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadStateModule() {
  // state.js refers to globals (POOLS, genId, timecodeToSeconds, audioCache,
  // STORAGE_KEY, etc.) that we stub minimally — we only exercise migrateCues
  // and migrateState, which depend on POOLS + the cue/action shape.
  const sandbox = {
    window: { CC: {} },
    console,
    POOLS: ['dimmer', 'position', 'gobo', 'color', 'beam', 'focus'],
    genId: () => 'id-' + Math.random().toString(36).slice(2),
    timecodeToSeconds: () => NaN,
    audioCache: new Map(),
    STORAGE_KEY: 'cuelistCompilerProject',
    STORAGE_KEY_MOODS: 'cuelistCompilerMoods',
    STORAGE_KEY_DEFAULTS: 'cuelistCompilerDefaults',
    STORAGE_KEY_POOLS: 'cuelistCompilerPools',
    localStorage: { getItem: () => null, setItem: () => {} },
  };
  vm.createContext(sandbox);
  const code = fs.readFileSync(path.resolve(__dirname, '..', 'js', 'state.js'), 'utf8');
  vm.runInContext(code, sandbox, { filename: 'state.js' });
  return sandbox.window.CC.state;
}

test('migrateCues: cues without includeStore/includeTc default to true', () => {
  const st = loadStateModule();
  const cues = [
    { n: 1, name: 'A', actions: [], fade: '', delay: '' },
    { n: 2, name: 'B', actions: [], fade: '', delay: '', includeStore: false },
    { n: 3, name: 'C', actions: [], fade: '', delay: '', includeTc: false },
    { n: 4, name: 'D', actions: [], fade: '', delay: '', includeStore: true, includeTc: true },
  ];
  st.migrateCues(cues);
  assert.strictEqual(cues[0].includeStore, true);
  assert.strictEqual(cues[0].includeTc, true);
  assert.strictEqual(cues[1].includeStore, false);  // existing false preserved
  assert.strictEqual(cues[1].includeTc, true);      // missing → true
  assert.strictEqual(cues[2].includeStore, true);   // missing → true
  assert.strictEqual(cues[2].includeTc, false);     // existing false preserved
  assert.strictEqual(cues[3].includeStore, true);
  assert.strictEqual(cues[3].includeTc, true);
});

test('newCue: fresh cue has includeStore=true and includeTc=true', () => {
  const st = loadStateModule();
  // newCue() reads activeSong() globally — stub the necessary globals
  global.state = { songs: [{ id: 'x', cues: [] }], activeSongId: 'x' };
  const cue = st.newCue();
  assert.strictEqual(cue.includeStore, true);
  assert.strictEqual(cue.includeTc, true);
  delete global.state;
});
```

- [ ] **Step 2: Run tests to verify they fail**

```
cd web && node --test test/state.test.js
```

Expected: FAIL — `includeStore`/`includeTc` undefined on migrated/new cues.

- [ ] **Step 3: Update `migrateCues` in `state.js`**

Edit `web/js/state.js`, function `migrateCues` (around line 93). Replace:

```javascript
function migrateCues(cues) {
  (cues || []).forEach(cue => {
    if (typeof cue.collapsed !== 'boolean') cue.collapsed = false;
    if (cue.position == null) cue.position = '';
    migrateActions(cue.actions);
  });
}
```

with:

```javascript
function migrateCues(cues) {
  (cues || []).forEach(cue => {
    if (typeof cue.collapsed !== 'boolean') cue.collapsed = false;
    if (cue.position == null) cue.position = '';
    if (typeof cue.includeStore !== 'boolean') cue.includeStore = true;
    if (typeof cue.includeTc !== 'boolean') cue.includeTc = true;
    migrateActions(cue.actions);
  });
}
```

- [ ] **Step 4: Update `newCue` and `appendCueWithTcAndResort` in `state.js`**

Edit `web/js/state.js`. In `newCue` (around line 27), the returned object becomes:

```javascript
return {
  n: maxN + 1,
  name: '',
  actions: [newAction()],
  fade: '',
  delay: '',
  collapsed: false,
  includeStore: true,
  includeTc: true
};
```

In `appendCueWithTcAndResort` (around line 40), the pushed cue object becomes:

```javascript
song.cues.push({
  n: 0,
  position: tc,
  name: '',
  actions: [newAction()],
  fade: '',
  delay: '',
  collapsed: false,
  includeStore: true,
  includeTc: true
});
```

- [ ] **Step 5: Update CSV import path in `state.js`**

In `importCsv` (around line 509) the per-row cue object becomes:

```javascript
cueList.push({
  n: isNaN(cueN) ? cueList.length + 1 : cueN,
  name: label,
  actions: [newAction()],
  fade: '',
  delay: '',
  collapsed: true,
  position,
  includeStore: true,
  includeTc: true
});
```

- [ ] **Step 6: Run state tests to verify they pass**

```
cd web && node --test test/state.test.js
```

Expected: PASS — both migration cases + `newCue` default cases pass.

- [ ] **Step 7: Commit**

```
git add web/js/state.js web/test/state.test.js
git commit -m "feat(state): per-cue includeStore/includeTc flags with migration"
```

---

## Task 2: Filter cues in `compile.js` emission

**Files:**
- Modify: `web/js/compile.js` (functions `buildLua` around line 58 → uses `songToLuaEntry`, `buildCmdLines` around line 110, `buildTcCmdLines` around line 166, `buildTcLua` around line 231)
- Modify: `web/test/tc.test.js` (add `includeTc` filter cases)
- Create: `web/test/compile.test.js` (new file for `buildLua`/`buildCmdLines` filter cases)

The filter happens **inside** each builder, not at the call sites. This keeps the offline `.lua` path and the live OSC path filtering identically — the v1.5 invariant.

For STORE filtering: a cue with `includeStore === false` is omitted entirely from the output (no `ClearAll`, no `Group`, no `At Preset`, no `Store`, no `Set`).

For TC filtering: a cue with `includeTc === false` is omitted from the `validCues` list **before** the existing `isValidSmpte` filter. The two conditions are independent and combine with AND.

- [ ] **Step 1: Write failing `compile.test.js` for STORE filter**

Create `web/test/compile.test.js`:

```javascript
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadCompile() {
  const sandbox = { window: { CC: {} }, console, FPS: 25 };
  vm.createContext(sandbox);
  for (const f of ['constants.js', 'util.js']) {
    const code = fs.readFileSync(path.resolve(__dirname, '..', 'js', f), 'utf8');
    vm.runInContext(code, sandbox, { filename: f });
  }
  sandbox.state = { songs: [], storeMode: 'Overwrite' };
  sandbox.defaults = {};
  const code = fs.readFileSync(path.resolve(__dirname, '..', 'js', 'compile.js'), 'utf8');
  vm.runInContext(code, sandbox, { filename: 'compile.js' });
  return sandbox.window.CC.compile;
}

function mkCue(n, name, opts) {
  return Object.assign({
    n, name,
    actions: [{ group: 'GRP', presets: { dimmer: { name: 'D80', fade: '', delay: '' } } }],
    fade: '', delay: '',
    includeStore: true, includeTc: true,
    position: ''
  }, opts || {});
}

test('buildCmdLines: skips cues with includeStore=false', () => {
  const compile = loadCompile();
  const songs = [{ sequence: 1, name: 'S', cues: [
    mkCue(1, 'A'),
    mkCue(2, 'B', { includeStore: false }),
    mkCue(3, 'C'),
  ]}];
  const out = compile.buildCmdLines(songs);
  const joined = out.join('\n');
  // The included cues both emit a Store line for their cue number.
  assert.ok(joined.includes('Store Sequence 1 Cue 1 "A"'), 'cue 1 must emit');
  assert.ok(joined.includes('Store Sequence 1 Cue 3 "C"'), 'cue 3 must emit');
  // The skipped cue must not appear in any Store line.
  assert.ok(!joined.includes('Cue 2 "B"'), 'cue 2 must not emit');
  // It must not emit a bare Cue 2 either (cue with empty name).
  assert.ok(!/Store Sequence 1 Cue 2( |\/)/.test(joined), 'cue 2 must not emit unnamed form');
});

test('buildCmdLines: includeTc=false does NOT filter STORE path', () => {
  const compile = loadCompile();
  const songs = [{ sequence: 1, name: 'S', cues: [
    mkCue(1, 'A', { includeTc: false }),
  ]}];
  const out = compile.buildCmdLines(songs);
  assert.ok(out.join('\n').includes('Store Sequence 1 Cue 1 "A"'));
});

test('buildLua: skips cues with includeStore=false from SONGS table', () => {
  const compile = loadCompile();
  const songs = [{ sequence: 1, name: 'S', cues: [
    mkCue(1, 'A'),
    mkCue(2, 'B', { includeStore: false }),
    mkCue(3, 'C'),
  ]}];
  const lua = compile.buildLua(songs, 'test');
  // The SONGS table holds only the kept cues.
  assert.ok(lua.includes('{n=1, name="A"'), 'cue 1 stays');
  assert.ok(lua.includes('{n=3, name="C"'), 'cue 3 stays');
  assert.ok(!lua.includes('{n=2, name="B"'), 'cue 2 omitted');
});

test('buildLua: all cues unchecked emits a song with empty cues={}', () => {
  const compile = loadCompile();
  const songs = [{ sequence: 1, name: 'S', cues: [
    mkCue(1, 'A', { includeStore: false }),
  ]}];
  const lua = compile.buildLua(songs, 'test');
  // The song still appears with an empty cue list; no Cue line inside.
  assert.ok(lua.includes('{name="S", seq=1, cues={'));
  assert.ok(!lua.includes('{n=1, name="A"'));
});
```

- [ ] **Step 2: Run to verify failure**

```
cd web && node --test test/compile.test.js
```

Expected: FAIL — both `buildLua` and `buildCmdLines` currently emit all cues.

- [ ] **Step 3: Add the filter to `buildCmdLines`**

Edit `web/js/compile.js`, function `buildCmdLines` (around line 110). Inside the `.forEach(cue => { ... })` block on line 116, before `out.push('ClearAll')`, add the skip:

```javascript
(song.cues || []).forEach(cue => {
  if (cue.includeStore === false) return;
  out.push('ClearAll');
  // ... existing body unchanged ...
});
```

- [ ] **Step 4: Add the filter to `songToLuaEntry`**

Edit `web/js/compile.js`, function `songToLuaEntry` (around line 17). Inside the `song.cues.forEach(cue => { ... })` on line 22, add the skip at the very top of the callback:

```javascript
song.cues.forEach(cue => {
  if (cue.includeStore === false) return;
  const actions = cue.actions
  // ... existing body unchanged ...
});
```

- [ ] **Step 5: Run `compile.test.js` to verify it passes**

```
cd web && node --test test/compile.test.js
```

Expected: PASS — STORE skip works in both paths.

- [ ] **Step 6: Add failing `includeTc` filter test to `tc.test.js`**

Edit `web/test/tc.test.js` and append (after the existing tests, before module end):

```javascript
test('buildTcCmdLines: skips cues with includeTc=false', () => {
  const compile = loadCompile();
  const song = { sequence: 1, name: 'S', cues: [
    { n: 1, name: 'A', position: '00:00:01:00', includeTc: true },
    { n: 2, name: 'B', position: '00:00:02:00', includeTc: false },
    { n: 3, name: 'C', position: '00:00:03:00', includeTc: true },
  ]};
  const out = compile.buildTcCmdLines([song]);
  assert.strictEqual(out.length, 1);
  // Only cues 1 and 3 appear; cue 2's rawtime (33554432) must NOT.
  assert.ok(out[0].includes('{{1,16777216},{3,50331648}}'),
    'expected only cues 1 and 3 in the events table');
  assert.ok(!out[0].includes('33554432'),
    'cue 2 rawtime must not be present');
});

test('buildTcLua: skips cues with includeTc=false from SONGS table', () => {
  const compile = loadCompile();
  const song = { sequence: 1, name: 'S', cues: [
    { n: 1, name: 'A', position: '00:00:01:00', includeTc: false },
    { n: 2, name: 'B', position: '00:00:02:00', includeTc: true },
  ]};
  const lua = compile.buildTcLua([song], 'Song: S');
  // Cue 2 is the only kept one.
  assert.ok(lua.includes('cues={{2,33554432}}'),
    'expected only cue 2 in SONGS cues');
  assert.ok(!lua.includes('{1,16777216}'),
    'cue 1 rawtime must not appear');
});

test('buildTcCmdLines: includeStore=false does NOT filter TC path', () => {
  const compile = loadCompile();
  const song = { sequence: 1, name: 'S', cues: [
    { n: 1, name: 'A', position: '00:00:01:00', includeStore: false, includeTc: true },
  ]};
  const out = compile.buildTcCmdLines([song]);
  assert.strictEqual(out.length, 1);
  assert.ok(out[0].includes('{{1,16777216}}'));
});
```

- [ ] **Step 7: Run TC tests to verify failure**

```
cd web && node --test test/tc.test.js
```

Expected: FAIL — TC builders do not filter by `includeTc`.

- [ ] **Step 8: Add the filter to `buildTcCmdLines`**

Edit `web/js/compile.js`, function `buildTcCmdLines` (around line 166). Modify the `validCues` filter chain on line 170:

```javascript
const validCues = (song.cues || [])
  .filter(c => c.includeTc !== false)
  .filter(c => isValidSmpte(c.position))
  .slice()
  .sort((a, b) => (parseFloat(a.n) || 0) - (parseFloat(b.n) || 0));
```

- [ ] **Step 9: Add the same filter to `buildTcLua`**

Edit `web/js/compile.js`, function `buildTcLua` (around line 231). Modify the inner cues filter chain (line 234):

```javascript
const cues = (song.cues || [])
  .filter(c => c.includeTc !== false)
  .filter(c => isValidSmpte(c.position))
  .slice()
  .sort((a, b) => (parseFloat(a.n) || 0) - (parseFloat(b.n) || 0));
```

- [ ] **Step 10: Run all tests to verify they pass**

```
cd web && node --test test/state.test.js test/tc.test.js test/compile.test.js test/transport.test.js
```

Expected: ALL PASS, including the existing SONG_1.json regression (every SONG_1 cue has `includeStore`/`includeTc` defaulting to true after migration → byte-identical output to baseline).

- [ ] **Step 11: Commit**

```
git add web/js/compile.js web/test/compile.test.js web/test/tc.test.js
git commit -m "feat(compile): filter cues by includeStore/includeTc in all emission paths"
```

---

## Task 3: Chip toggles on the cue card

**Files:**
- Modify: `web/js/render.js` (function `renderCue` around line 191)
- Modify: `web/css/styles.css` (append new `.cue-include-chip` rules)

The two chips render in the cue header row, immediately after the `cue-tc-capture` button (the 🎯 button) and before the cue-name input. This keeps them near other per-cue metadata. They render in both expanded and collapsed states (so the operator can see at a glance which cues are excluded).

- [ ] **Step 1: Modify `renderCue` to inject the two chips**

Edit `web/js/render.js`, function `renderCue` (around line 191). Locate the `hdr.innerHTML = `...`;` block on line 201. Insert the two chips between the `cue-tc-capture` button and the `cue-name` input:

```javascript
hdr.innerHTML = `
  <button class="chevron" title="${cue.collapsed ? 'Expand' : 'Collapse'}">${chev}</button>
  <input type="number" step="0.1" class="cue-num" value="${escapeHtml(cue.n)}" title="Cue number">
  <input type="text" class="${tcCls}" placeholder="HH:MM:SS:FF" value="${tcVal}" title="Timecode (25fps SMPTE) — empty = excluded from TC export">
  <button class="icon-btn cue-tc-capture" title="Capture from audio playhead">🎯</button>
  <button class="cue-include-chip cue-include-store ${cue.includeStore !== false ? 'on' : 'off'}" title="Include this cue's preset Store in Send / Export .lua">STORE</button>
  <button class="cue-include-chip cue-include-tc ${cue.includeTc !== false ? 'on' : 'off'}" title="Include this cue's TC event in Send TC / Export TC .lua">TC</button>
  <input type="text" class="cue-name" placeholder="Cue name (Intro, Verse, Chorus...)" value="${escapeHtml(cue.name)}">
  ${cue.collapsed ? `<span class="cue-summary">${escapeHtml(cueSummary(cue))}</span>` : ''}
  <button class="icon-btn danger" title="Remove cue">&times;</button>
`;
```

- [ ] **Step 2: Wire the click handlers**

In the same function, after the `'.cue-tc-capture'` handler (around line 233-240), add:

```javascript
hdr.querySelector('.cue-include-store').addEventListener('click', e => {
  e.stopPropagation();
  cue.includeStore = cue.includeStore === false;  // toggle: false→true, anything else→false
  saveState();
  render();
});
hdr.querySelector('.cue-include-tc').addEventListener('click', e => {
  e.stopPropagation();
  cue.includeTc = cue.includeTc === false;
  saveState();
  render();
});
```

Note on the toggle expression: `cue.includeStore === false` evaluates to `true` only when currently false, so clicking flips false→true and (true or undefined)→false. This matches the migrated-default semantics: missing or `true` are both "included," click excludes.

- [ ] **Step 3: Append Amber-HUD CSS for the chips**

Edit `web/css/styles.css`. Append at the end of the file:

```css
/* Cue include chips — STORE and TC toggles in the cue card header.
   Amber HUD vocabulary: solid amber fill when on, outline + dim text when off. */
.cue-include-chip {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0 8px;
  height: 24px;
  margin: 0 2px;
  font-family: var(--hud-mono, ui-monospace, SFMono-Regular, Menlo, monospace);
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.06em;
  border-radius: 4px;
  cursor: pointer;
  user-select: none;
  transition: background 80ms ease, color 80ms ease, border-color 80ms ease;
  flex-shrink: 0;
}
.cue-include-chip.on {
  background: var(--hud-amber, #f5a623);
  color: #1a1208;
  border: 1px solid var(--hud-amber, #f5a623);
}
.cue-include-chip.on:hover {
  background: var(--hud-amber-hi, #ffb73a);
  border-color: var(--hud-amber-hi, #ffb73a);
}
.cue-include-chip.off {
  background: transparent;
  color: var(--hud-dim, #7a7468);
  border: 1px solid var(--hud-dim, #7a7468);
}
.cue-include-chip.off:hover {
  color: var(--hud-amber, #f5a623);
  border-color: var(--hud-amber, #f5a623);
}
```

The `var(...)` fallbacks ensure the chips render correctly even if the Amber HUD token names differ — find/replace later if the project ends up using different variable names (the chips just won't look HUD-themed in that case, they'll use the fallback amber).

- [ ] **Step 4: Manual smoke test**

```
cd desktop && npm start
```

Verify in the open Electron window:

1. Load SONG_1.json (Load Project) — every cue card shows both chips in "ON" state (solid amber).
2. Click STORE on one cue — chip turns "OFF" (outline). Page does not reload, only that chip changes.
3. Click TC on another cue — same.
4. Refresh window (Ctrl+R) — chip states persist (localStorage round-trip).
5. Save Project → reopen → states still correct (JSON round-trip).
6. Collapse a cue (chevron) — chips still visible in the collapsed header.

If any check fails, fix in place and retry. Close the dev window afterward.

- [ ] **Step 5: Commit**

```
git add web/js/render.js web/css/styles.css
git commit -m "feat(web-ui): per-cue STORE/TC include chip toggles on cue cards"
```

---

## Task 4: Left trim handle on the audio timeline

**Files:**
- Modify: `web/js/audio.js` (DOM template around line 662, wiring around line 803, `redrawAudioBody` around line 1206, drag handler block around line 1296)
- Modify: `web/css/styles.css` (the `.trim-handle` block around line 1340)

Handle math: position the left handle at the song-time corresponding to `audioTrim.startS` projected through the current viewport, same way the end handle uses `audioTrim.endS` minus `startS`. Since the left edge represents the audio's starting point in song-time, it is always at `songT = 0` when `startS >= 0`. When `startS < 0` (audio shifted back behind the timeline), the handle lives at `songT = -startS` (a positive song-time offset).

Wait — re-derive. The body-drag model says `songT = fileT - startS`. The audio file's first sample (`fileT = 0`) maps to `songT = -startS`. So:
- If `startS = 0`: the audio's first sample is at song-time 0 — handle at the timeline's zero.
- If `startS = 5` (operator cropped the head by 5s): audio's first KEPT sample is at song-time 0 still (the trim hides `fileT in [0, 5)`); the boundary the operator cares about — "where does the kept audio begin?" — is at song-time 0.
- If `startS = -3` (operator shifted the audio 3s later): `fileT=0` maps to `songT = 3`; the audio starts at song-time 3.

So the handle's visible song-time is `max(0, -startS)` when the audio has been shifted forward, and the handle drag changes `startS` directly. Simpler: render at `songT = -startS`, let the viewport-clamp logic hide it when it falls outside (negative side).

- [ ] **Step 1: Add the DOM element**

Edit `web/js/audio.js`, in the panel-template `innerHTML` template literal (around line 662). The current `<div id="timeline">` block ends with `<div class="trim-handle" id="trimEndHandle" ...></div>`. Insert the start handle right BEFORE it:

```javascript
      <div class="markers" id="markers"></div>
      <div class="playhead" id="playhead" style="left:0px"></div>
      <div class="trim-handle trim-handle-start" id="trimStartHandle" title="Audio start — drag to cut the head"></div>
      <div class="trim-handle" id="trimEndHandle" title="Audio end — drag to cut the tail"></div>
```

- [ ] **Step 2: Wire the start-handle mousedown + dblclick**

Edit `web/js/audio.js`, around line 803, after the existing `endHandle` wiring (line 803-810). Add:

```javascript
const startHandle = document.getElementById('trimStartHandle');
if (startHandle) {
  startHandle.addEventListener('mousedown', startStartHandleDrag);
  startHandle.addEventListener('dblclick', () => {
    const song = activeSong();
    if (song && song.audioTrim) {
      song.audioTrim.startS = 0;
      redrawAudioBody();
      saveState();
    }
  });
}
```

- [ ] **Step 3: Add `positionStartHandle` and call it from `redrawAudioBody`**

Edit `web/js/audio.js`, function `redrawAudioBody` (around line 1206). After the existing `positionEndHandle();` call (line 1217), add `positionStartHandle();`:

```javascript
function redrawAudioBody() {
  if (!audioBuffer) return;
  const song = activeSong();
  const trim = (song && song.audioTrim) ? song.audioTrim : { startS: 0, endS: null };
  const dur = audioBuffer.duration;
  const wl = document.getElementById('waveL');
  if (wl) drawWaveform(wl, audioBuffer.getChannelData(0), dur, trim);
  if (audioBuffer.numberOfChannels >= 2) {
    const wr = document.getElementById('waveR');
    if (wr) drawWaveform(wr, audioBuffer.getChannelData(1), dur, trim);
  }
  positionEndHandle();
  positionStartHandle();
  updatePlayhead();
}
```

Then define `positionStartHandle` next to `positionEndHandle` (after line 1239):

```javascript
function positionStartHandle() {
  const song = activeSong();
  if (!song || !audioBuffer) return;
  const trim = song.audioTrim || { startS: 0, endS: null };
  const dur = audioBuffer.duration;
  const handle = document.getElementById('trimStartHandle');
  if (!handle) return;
  const vp = viewportOf(song, dur);
  // Audio's first sample (fileT=0) maps to songT = -startS.
  const audioStartSong = -trim.startS;
  // Hide if outside the current viewport.
  if (audioStartSong < vp.offsetS || audioStartSong > vp.offsetS + vp.visibleDur) {
    handle.style.display = 'none';
    return;
  }
  handle.style.display = '';
  const pct = (audioStartSong - vp.offsetS) / vp.visibleDur;
  handle.style.left = (pct * 100) + '%';
}
```

- [ ] **Step 4: Add `startStartHandleDrag` + move/end handlers**

Edit `web/js/audio.js`, immediately after `onEndHandleDragEnd` (around line 1337). Add:

```javascript
function startStartHandleDrag(evt) {
  if (!audioBuffer) return;
  const song = activeSong();
  if (song && song.audioLocked) return;       // 🔒 track is locked
  const tl = document.getElementById('timeline');
  if (!tl) return;
  evt.preventDefault();
  evt.stopPropagation();
  trimDragState = {
    kind: 'start',
    timelineRect: tl.getBoundingClientRect(),
    durationS: audioBuffer.duration
  };
  document.body.style.cursor = 'ew-resize';
  window.addEventListener('mousemove', onStartHandleDragMove);
  window.addEventListener('mouseup', onStartHandleDragEnd);
}

function onStartHandleDragMove(evt) {
  if (!trimDragState || trimDragState.kind !== 'start') return;
  const song = activeSong();
  if (!song) return;
  if (!song.audioTrim) song.audioTrim = { startS: 0, endS: null };
  const { timelineRect, durationS } = trimDragState;
  const vp = viewportOf(song, durationS);
  let pxX = evt.clientX - timelineRect.left;
  pxX = Math.max(0, Math.min(timelineRect.width, pxX));
  const songT = vp.offsetS + (pxX / timelineRect.width) * vp.visibleDur;
  // Inverse of positionStartHandle: songT = -startS  →  startS = -songT.
  // Clamp aligned with body-drag (allows negative startS) and end-handle minimum gap.
  const endSEffective = song.audioTrim.endS != null ? song.audioTrim.endS : durationS;
  const minStartS = -(durationS - 0.5);
  const maxStartS = endSEffective - 0.5;
  song.audioTrim.startS = Math.max(minStartS, Math.min(maxStartS, -songT));
  redrawAudioBody();
}

function onStartHandleDragEnd() {
  if (!trimDragState || trimDragState.kind !== 'start') return;
  trimDragState = null;
  document.body.style.cursor = '';
  window.removeEventListener('mousemove', onStartHandleDragMove);
  window.removeEventListener('mouseup', onStartHandleDragEnd);
  saveState();
}
```

- [ ] **Step 5: Export the new functions on `window.CC.audio`**

Edit `web/js/audio.js`, the public surface block (line 1349-1362). Extend the audio-mobile trim model line:

```javascript
  // audio-mobile trim model
  redrawAudioBody, positionEndHandle, positionStartHandle,
  startAudioBodyDrag, startEndHandleDrag, startStartHandleDrag, resetAudioTrim,
```

- [ ] **Step 6: CSS — mirror handle for the left side**

Edit `web/css/styles.css`, after the existing `.trim-handle:hover::after` block (around line 1363). Append:

```css
/* Left trim handle uses the same .trim-handle base styles, but mirrors the
   accent bar to the right edge of the 8px hit zone so it points "into" the
   waveform (kept audio is to the right of the handle). */
#timeline .trim-handle-start {
  border-right: none;
  border-left: 2px solid #f8f8f8;
  transform: translateX(-4px);   /* same hit-zone centering as the right handle */
}
```

- [ ] **Step 7: Manual smoke test**

```
cd desktop && npm start
```

Verify:

1. Load SONG_1.json — left handle visible at song-time 0 (timeline's left edge).
2. Drag the left handle to the right by ~20px — `startS` increases (head trimmed), waveform shifts visually.
3. Drag back past zero — `startS` goes negative (audio shifts later in song-time), waveform's start now sits to the right of timeline zero, handle follows.
4. Body-drag still works on the waveform area — does NOT also fire the start handle (the `trim-handle` class guard at line 1243 already covers the new element).
5. Right end handle still works for `endS`.
6. Double-click the left handle — `startS` snaps back to 0.
7. While dragging the left handle, the right handle stays put (endS unchanged).
8. The handle hides correctly if you pan/zoom the viewport so the audio start scrolls off-screen.

If any check fails, fix and retry. Close the dev window.

- [ ] **Step 8: Commit**

```
git add web/js/audio.js web/css/styles.css
git commit -m "feat(audio): restore left trim handle (startS) symmetric to end handle"
```

---

## Task 5: Update the MA3 command contract

**Files:**
- Modify: `shared/ma3-command-spec.md`

- [ ] **Step 1: Find the right insertion point**

Search the file for the section that describes "preset store" emission (likely near the top under a "Store path" or similar heading). Use Grep:

```
Grep pattern="Store|Timecode show" path="shared/ma3-command-spec.md" output_mode="content" -n=true
```

- [ ] **Step 2: Add a "Cue inclusion filters" subsection**

In `shared/ma3-command-spec.md`, add a new short subsection (placement: right after the cue-iteration rules in the Store-path section, and right after the cue-iteration rules in the Timecode-show section — or once at the top of the document if there's a "Common rules" area). Use this content:

```markdown
### Cue inclusion filters

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
```

- [ ] **Step 3: Commit**

```
git add shared/ma3-command-spec.md
git commit -m "docs(spec): cue includeStore/includeTc filters"
```

---

## Task 6: Final verification

- [ ] **Step 1: Run the full web test suite**

```
cd web && node --test test/state.test.js test/tc.test.js test/compile.test.js test/transport.test.js test/audio-helpers.test.js test/restyle-guard.test.js
```

Expected: ALL PASS. The SONG_1.json regression in `tc.test.js` must remain green (migration fills the flags, defaults match prior behavior).

- [ ] **Step 2: End-to-end smoke in the desktop app**

```
cd desktop && npm start
```

Walk through:

1. New empty project → add 3 cues → 1 cue uncheck STORE → Export current .lua → verify the unchecked cue does NOT appear in the SONGS table.
2. Reset, add 3 cues with TC positions → uncheck TC on the middle one → Export TC current .lua → verify only 2 events emitted in the rawtime list.
3. Toggle chips back on → re-export → all 3 emitted in each path.
4. Drag left trim handle → save project → reopen → handle remembers position.

- [ ] **Step 3: Commit any fixup if needed**

If verification turned up nothing, skip. Otherwise: a short fix commit with a `fix(...)` prefix.

- [ ] **Step 4: Open a PR**

```
git push -u origin feat/cue-inclusion-flags-and-left-trim-handle
gh pr create --title "Per-cue STORE/TC include chips + restore left trim handle" --body "$(cat <<'EOF'
## Summary
- Adds `includeStore` and `includeTc` boolean flags per cue, with HUD chip toggles in the cue card header (default ON, with migration for old projects).
- All four emission paths (`buildLua`, `buildCmdLines`, `buildTcLua`, `buildTcCmdLines`) skip excluded cues.
- Restores a left trim handle on the audio timeline, symmetric to the existing right end handle. Body-drag remains.

Spec: `docs/superpowers/specs/2026-06-12-cue-inclusion-flags-and-left-trim-handle-design.md`
Plan: `docs/superpowers/plans/2026-06-12-cue-inclusion-flags-and-left-trim-handle.md`

## Test plan
- [x] `node --test test/state.test.js test/tc.test.js test/compile.test.js test/transport.test.js` — all pass locally
- [x] Desktop smoke: export .lua / TC .lua with mixed chip states emits only the kept cues
- [x] Left trim handle drag / dblclick reset / persistence across reload
EOF
)"
```

---

## Notes for the implementer

- **Single source of truth.** Any new emission rule goes in `compile.js`. Do not duplicate the filter at call sites (`exportLua`, `exportAllLua`, OSC sender). They already pass through `buildLua`/`buildCmdLines`/`buildTcLua`/`buildTcCmdLines`.
- **iOS untouched.** Do not modify `ios/` files. The flags ride along in the project JSON; iOS will ignore them.
- **Migration matters.** The `migrateCues` change is the safety net that makes existing projects (including SONG_1.json regression fixture) keep working without code changes anywhere else.
- **Spec amendment.** The spec was amended (`dfca567`) to align the left-handle clamp with the audio-mobile body-drag model (allowing negative `startS`). Use the formula in Task 4 Step 4, not the original spec's `[0, endS−MIN]` line.
