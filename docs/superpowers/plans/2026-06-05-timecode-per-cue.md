# Timecode per Cue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the operator attach a SMPTE position per cue (already present in the data model from CuePoints import) and push those positions to grandMA3 as Timecode events via two new toolbar buttons (`Send TC current → MA` / `Send TC all → MA`), using the Cmd-line syntax verified live on 2026-06-05.

**Architecture:** Reuse the existing `cue.position` field (no data-model change). Add a pure-function `buildTcCmdLines(songs)` in `compile.js` that emits the cleanup + Store + Set Property 'time' sequence per song. Wire two toolbar buttons through `osc.js` using the existing `sendCmdLinesViaOsc()` pipeline. Add a per-cue input + 🎯 capture button in the cue card (`render.js`) that calls a tiny helper in `audio.js`. Append the new contract to `shared/ma3-command-spec.md`.

**Tech Stack:** Plain JS (no build), Node's `node:test` for unit tests, existing `vm` sandbox pattern from `web/test/transport.test.js`.

**Spec:** `docs/superpowers/specs/2026-06-05-timecode-per-cue-design.md`

---

## File Map

**Modify:**
- `web/js/util.js` — add `isValidSmpte(s)` validator
- `web/js/audio.js` — add `captureCurrentPlayheadAsSmpte()` helper
- `web/js/compile.js` — add `buildTcCmdLines(songs)` + `buildTcLua(songs)` + `exportTcLua()` + `exportAllTcLua()`
- `web/js/osc.js` — add `sendTcCurrentViaOsc()` + `sendTcAllViaOsc()`
- `web/js/render.js` — add TC input + 🎯 button in `renderCue()` header
- `web/js/main.js` — wire 4 new toolbar buttons (`sendTcOscCurrent`, `sendTcOscAll`, `exportTc`, `exportTcAll`)
- `web/index.html` — add 4 new toolbar buttons + dependency note in subtitle
- `web/css/styles.css` — styles for `.cue-tc`, `.cue-tc-capture`, invalid state
- `shared/ma3-command-spec.md` — append `## Timecode show per song (optional)` section
- `README.md` — pre-conditions note (1 paragraph)

**Create:**
- `web/test/tc.test.js` — unit tests for `buildTcCmdLines` + `isValidSmpte` + capture helper
- `examples/SONG_1.tc.cmdlines.txt` — golden fixture for regression test

---

## Task 1: SMPTE validator in `util.js`

**Files:**
- Modify: `web/js/util.js` (append after `secondsToMMSS`)
- Test: `web/test/tc.test.js` (create)

- [ ] **Step 1.1: Create failing test for `isValidSmpte`**

Create file `web/test/tc.test.js`:

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadModules(files) {
  const sandbox = { window: { CC: {} }, console, FPS: 25 };
  vm.createContext(sandbox);
  for (const f of files) {
    const code = fs.readFileSync(path.resolve(__dirname, '..', 'js', f), 'utf8');
    vm.runInContext(code, sandbox, { filename: f });
  }
  return sandbox;
}

test('isValidSmpte: accepts well-formed SMPTE at 25fps', () => {
  const { window: { CC: { util } } } = loadModules(['util.js']);
  assert.strictEqual(util.isValidSmpte('00:00:00:00'), true);
  assert.strictEqual(util.isValidSmpte('00:01:23:12'), true);
  assert.strictEqual(util.isValidSmpte('23:59:59:24'), true); // FF=24 max at 25fps
});

test('isValidSmpte: rejects out-of-range and malformed', () => {
  const { window: { CC: { util } } } = loadModules(['util.js']);
  assert.strictEqual(util.isValidSmpte(''), false);
  assert.strictEqual(util.isValidSmpte('not smpte'), false);
  assert.strictEqual(util.isValidSmpte('1:2:3:4'), false);    // not zero-padded
  assert.strictEqual(util.isValidSmpte('00:60:00:00'), false); // MM >= 60
  assert.strictEqual(util.isValidSmpte('00:00:60:00'), false); // SS >= 60
  assert.strictEqual(util.isValidSmpte('00:00:00:25'), false); // FF >= FPS (25)
  assert.strictEqual(util.isValidSmpte(null), false);
  assert.strictEqual(util.isValidSmpte(undefined), false);
});
```

- [ ] **Step 1.2: Run test, verify it fails**

```
cd web && node --test test/tc.test.js
```

Expected: FAIL with `TypeError: util.isValidSmpte is not a function`.

- [ ] **Step 1.3: Implement `isValidSmpte` in `util.js`**

Append after `secondsToMMSS` (around line 26) and before `genId`:

```js
function isValidSmpte(s) {
  if (typeof s !== 'string') return false;
  const m = /^(\d{2}):(\d{2}):(\d{2}):(\d{2})$/.exec(s);
  if (!m) return false;
  const [, , mm, ss, ff] = m;
  return Number(mm) < 60 && Number(ss) < 60 && Number(ff) < FPS;
}
```

Then add `isValidSmpte` to the `CC.util` manifest at the bottom of the file:

```js
CC.util = { timecodeToSeconds, secondsToTimecode, secondsToMMSS, isValidSmpte, genId, escapeHtml, download };
```

- [ ] **Step 1.4: Run test, verify it passes**

```
cd web && node --test test/tc.test.js
```

Expected: both `isValidSmpte` tests PASS.

- [ ] **Step 1.5: Commit**

```
git add web/js/util.js web/test/tc.test.js
git commit -m "feat(web): isValidSmpte validator for HH:MM:SS:FF at 25fps"
```

---

## Task 2: `captureCurrentPlayheadAsSmpte()` in `audio.js`

**Files:**
- Modify: `web/js/audio.js` (append before public surface)
- Test: `web/test/tc.test.js` (extend)

- [ ] **Step 2.1: Add failing test**

Append to `web/test/tc.test.js`:

```js
test('captureCurrentPlayheadAsSmpte: returns null when no audio loaded', () => {
  const sb = loadModules(['util.js']);
  // Inject a minimal audio.js scope using its captureCurrentPlayheadAsSmpte
  // (we don't load audio.js directly because it needs DOM; we test the pure helper)
  // For the pure-helper version, the function is:
  function captureCurrentPlayheadAsSmpte(audioEl) {
    if (!audioEl || isNaN(audioEl.currentTime)) return null;
    return sb.window.CC.util.secondsToTimecode(audioEl.currentTime);
  }
  assert.strictEqual(captureCurrentPlayheadAsSmpte(null), null);
  assert.strictEqual(captureCurrentPlayheadAsSmpte({ currentTime: NaN }), null);
});

test('captureCurrentPlayheadAsSmpte: converts currentTime to SMPTE', () => {
  const sb = loadModules(['util.js']);
  function captureCurrentPlayheadAsSmpte(audioEl) {
    if (!audioEl || isNaN(audioEl.currentTime)) return null;
    return sb.window.CC.util.secondsToTimecode(audioEl.currentTime);
  }
  assert.strictEqual(captureCurrentPlayheadAsSmpte({ currentTime: 0 }), '00:00:00:00');
  assert.strictEqual(captureCurrentPlayheadAsSmpte({ currentTime: 65.4 }), '00:01:05:10');
  // 5s + 0.4 * 25 = 10 frames
});
```

- [ ] **Step 2.2: Run, verify pass**

The function under test is defined inline in the test. Tests should pass immediately — this step exists to lock the expected behavior.

```
cd web && node --test test/tc.test.js
```

Expected: 4 tests passing (2 from Task 1 + 2 new).

- [ ] **Step 2.3: Implement in `audio.js`**

Open `web/js/audio.js`. Find the public surface section at the bottom (look for `window.CC = window.CC || {}` and `CC.audio = ...`).

Just before the public surface, add:

```js
function captureCurrentPlayheadAsSmpte() {
  if (!audioEl || isNaN(audioEl.currentTime)) return null;
  return secondsToTimecode(audioEl.currentTime);
}
```

(Uses the global `audioEl` and `secondsToTimecode` already in scope from `util.js`.)

Add `captureCurrentPlayheadAsSmpte` to the `CC.audio` manifest export.

- [ ] **Step 2.4: Commit**

```
git add web/js/audio.js web/test/tc.test.js
git commit -m "feat(web): capture audio playhead as SMPTE (audio.js)"
```

---

## Task 3: `buildTcCmdLines(songs)` core in `compile.js`

**Files:**
- Modify: `web/js/compile.js` (append after `buildCmdLines`)
- Test: `web/test/tc.test.js` (extend)

- [ ] **Step 3.1: Add failing tests**

Append to `web/test/tc.test.js`:

```js
function loadCompile() {
  // compile.js depends on POOLS, POOL_NUM (constants), and reads global state/defaults.
  // For these tests we don't need state/defaults — only TC builders, which are pure.
  const sb = loadModules(['constants.js', 'util.js']);
  // Inject empty state + defaults so compile.js doesn't throw on top-level access.
  sb.state = { songs: [], storeMode: 'Overwrite' };
  sb.defaults = {};
  const code = fs.readFileSync(path.resolve(__dirname, '..', 'js', 'compile.js'), 'utf8');
  vm.runInContext(code, sb, { filename: 'compile.js' });
  return sb.window.CC.compile;
}

test('buildTcCmdLines: skips songs with no cues having valid position', () => {
  const compile = loadCompile();
  const song = { sequence: 12, name: 'S1', cues: [
    { n: 1, name: 'A', position: '' },
    { n: 2, name: 'B', position: 'bogus' },
  ]};
  assert.deepStrictEqual(compile.buildTcCmdLines([song]), []);
});

test('buildTcCmdLines: emits cleanup + Store + Set per valid cue', () => {
  const compile = loadCompile();
  const song = { sequence: 12, name: 'S1', cues: [
    { n: 1, name: 'INTRO',  position: '00:00:05:00' },   // 5.0 s
    { n: 2, name: 'VERSE',  position: '00:00:10:12' },   // 10 + 12/25 = 10.48 s
    { n: 3, name: 'BAD',    position: '99:99:99:99' },   // invalid → skipped
  ]};
  const out = compile.buildTcCmdLines([song]);
  // first 200 are deletes
  for (let i = 0; i < 200; i++) {
    assert.strictEqual(out[i], 'Delete Timecode 12.1.1.1.1.1 /NoConfirmation');
  }
  // then 2 events (cue 1 and 2; cue 3 skipped)
  assert.strictEqual(out[200], "Store Timecode 12.1.1.1.1 'Goto Cue 1 Sequence 12' /NoConfirmation");
  assert.strictEqual(out[201], "Set Timecode 12.1.1.1.1.1 Property 'time' 5");
  assert.strictEqual(out[202], "Store Timecode 12.1.1.1.1 'Goto Cue 2 Sequence 12' /NoConfirmation");
  assert.strictEqual(out[203], "Set Timecode 12.1.1.1.1.2 Property 'time' 10.48");
  assert.strictEqual(out.length, 204);
});

test('buildTcCmdLines: handles multiple songs, sorted cues by n ascending', () => {
  const compile = loadCompile();
  const songs = [
    { sequence: 1, name: 'A', cues: [
      { n: 2, name: '', position: '00:00:02:00' },
      { n: 1, name: '', position: '00:00:01:00' },
    ]},
    { sequence: 2, name: 'B', cues: [
      { n: 1, name: '', position: '00:00:00:12' },
    ]},
  ];
  const out = compile.buildTcCmdLines(songs);
  // Song A: 200 deletes + 2 events (n=1 first, n=2 second)
  // Song B: 200 deletes + 1 event
  assert.strictEqual(out.length, 200 + 4 + 200 + 2);
  assert.strictEqual(out[200], "Store Timecode 1.1.1.1.1 'Goto Cue 1 Sequence 1' /NoConfirmation");
  assert.strictEqual(out[201], "Set Timecode 1.1.1.1.1.1 Property 'time' 1");
  assert.strictEqual(out[202], "Store Timecode 1.1.1.1.1 'Goto Cue 2 Sequence 1' /NoConfirmation");
  assert.strictEqual(out[203], "Set Timecode 1.1.1.1.1.2 Property 'time' 2");
  assert.strictEqual(out[404], "Store Timecode 2.1.1.1.1 'Goto Cue 1 Sequence 2' /NoConfirmation");
  assert.strictEqual(out[405], "Set Timecode 2.1.1.1.1.1 Property 'time' 0.48");
});

test('buildTcCmdLines: returns [] for empty input', () => {
  const compile = loadCompile();
  assert.deepStrictEqual(compile.buildTcCmdLines([]), []);
});
```

- [ ] **Step 3.2: Run, verify fail**

```
cd web && node --test test/tc.test.js
```

Expected: `TypeError: compile.buildTcCmdLines is not a function` on all 4 new tests.

- [ ] **Step 3.3: Implement in `compile.js`**

Append after `buildCmdLines` (around line 132) and before `exportLua`:

```js
// Timecode events — see shared/ma3-command-spec.md §"Timecode show per song".
// Pre-conditions (operator manual): Sequence N, TC pool N, and Track at .1.1
// with target=Sequence N must exist on MA3. Overwrite-only behavior: wipes
// existing events at <N>.1.1.1.1 with up to 200 deletes (excess fail silently).
function buildTcCmdLines(songs) {
  const out = [];
  (songs || []).forEach(song => {
    const seq = parseInt(song.sequence) || 1;
    const validCues = (song.cues || [])
      .filter(c => isValidSmpte(c.position))
      .slice()
      .sort((a, b) => (parseFloat(a.n) || 0) - (parseFloat(b.n) || 0));
    if (validCues.length === 0) return;
    // cleanup
    for (let i = 0; i < 200; i++) {
      out.push(`Delete Timecode ${seq}.1.1.1.1.1 /NoConfirmation`);
    }
    // add events
    validCues.forEach((cue, i) => {
      const eventIdx = i + 1;
      const seconds = timecodeToSeconds(cue.position);
      // trim trailing zeros for compactness (5.0 -> 5, 10.48 -> 10.48)
      const sStr = Number.isInteger(seconds) ? String(seconds) : String(+seconds.toFixed(6)).replace(/\.?0+$/, '');
      out.push(`Store Timecode ${seq}.1.1.1.1 'Goto Cue ${cue.n} Sequence ${seq}' /NoConfirmation`);
      out.push(`Set Timecode ${seq}.1.1.1.1.${eventIdx} Property 'time' ${sStr}`);
    });
  });
  return out;
}
```

Add `buildTcCmdLines` to the `CC.compile` manifest at the bottom.

- [ ] **Step 3.4: Run, verify pass**

```
cd web && node --test test/tc.test.js
```

Expected: all 8 tests pass (2 isValidSmpte + 2 capture + 4 buildTcCmdLines).

- [ ] **Step 3.5: Commit**

```
git add web/js/compile.js web/test/tc.test.js
git commit -m "feat(web): buildTcCmdLines — Overwrite-only TC events via Cmd-line"
```

---

## Task 4: `buildTcLua(songs)` for paste-into-plugin export

**Files:**
- Modify: `web/js/compile.js`
- Test: `web/test/tc.test.js`

- [ ] **Step 4.1: Add failing test**

Append to `web/test/tc.test.js`:

```js
test('buildTcLua: wraps buildTcCmdLines output in Lua Cmd() calls', () => {
  const compile = loadCompile();
  const song = { sequence: 12, name: 'S', cues: [
    { n: 1, name: 'A', position: '00:00:05:00' },
  ]};
  const lua = compile.buildTcLua([song], 'Song: S');
  // header line
  assert.match(lua, /-- Generated by Cuelist Compiler/);
  assert.match(lua, /-- Song: S/);
  // first delete wrapped
  assert.match(lua, /Cmd\('Delete Timecode 12\.1\.1\.1\.1\.1 \/NoConfirmation'\)/);
  // store event wrapped (note nested single quotes in Lua require concat or escape)
  assert.match(lua, /Store Timecode 12\.1\.1\.1\.1 \\?'Goto Cue 1 Sequence 12\\?'/);
  // returns main per gma3 plugin convention
  assert.match(lua, /return main/);
});
```

- [ ] **Step 4.2: Run, verify fail**

```
cd web && node --test test/tc.test.js
```

Expected: `compile.buildTcLua is not a function`.

- [ ] **Step 4.3: Implement `buildTcLua` in `compile.js`**

Append after `buildTcCmdLines`:

```js
function buildTcLua(songs, headerTitle) {
  const cmds = buildTcCmdLines(songs);
  const lines = [];
  lines.push('-- Generated by Cuelist Compiler — TIMECODE EVENTS');
  lines.push(`-- ${headerTitle}`);
  lines.push(`-- Generated: ${new Date().toISOString()}`);
  lines.push('-- PRE-CONDITION: TC pool + Track (target=Sequence) must exist on MA3.');
  lines.push('-- BEHAVIOR: deletes up to 200 existing events per song, then adds new ones.');
  lines.push('');
  lines.push('local function main()');
  lines.push('  Printf("Cuelist Compiler TC: applying " .. ' + cmds.length + ' .. " commands")');
  cmds.forEach(line => {
    // Lua single-quote escape: ' -> \'
    const escaped = line.replace(/'/g, "\\'");
    lines.push(`  Cmd('${escaped}')`);
  });
  lines.push('  Printf("Cuelist Compiler TC: done.")');
  lines.push('end');
  lines.push('');
  lines.push('return main');
  return lines.join('\n');
}

function exportTcLua() {
  const song = activeSong();
  if (!song) return;
  const lines = buildTcCmdLines([song]);
  if (lines.length === 0) { alert('No cues with a valid TC position in the active song.'); return; }
  const content = buildTcLua([song], `Song TC: ${song.name || '(untitled)'}`);
  const filename = (song.name || 'song').replace(/[^a-zA-Z0-9_\-]+/g, '_') + '.tc.lua';
  download(content, filename, 'text/plain');
}

function exportAllTcLua() {
  const songs = state.songs.filter(s => (s.cues || []).some(c => isValidSmpte(c.position)));
  if (songs.length === 0) { alert('No songs have any cues with a valid TC position.'); return; }
  const content = buildTcLua(songs, `Show TC: ${songs.length} song(s)`);
  download(content, 'show.tc.lua', 'text/plain');
}
```

Add to the `CC.compile` manifest: `buildTcCmdLines, buildTcLua, exportTcLua, exportAllTcLua`.

- [ ] **Step 4.4: Run, verify pass**

```
cd web && node --test test/tc.test.js
```

Expected: 9 tests passing.

- [ ] **Step 4.5: Commit**

```
git add web/js/compile.js web/test/tc.test.js
git commit -m "feat(web): buildTcLua + exportTcLua for paste-into-plugin flow"
```

---

## Task 5: TC input + 🎯 button in cue card (`render.js`)

**Files:**
- Modify: `web/js/render.js` (around `renderCue`, line ~191)
- Modify: `web/css/styles.css` (append)

- [ ] **Step 5.1: Inspect existing cue header markup**

Open `web/js/render.js` and locate `renderCue(song, cue, ci)` (around line 191). The header section has chevron, `.cue-num` (number input), `.cue-name` (text input), summary (if collapsed), remove button.

We add a `.cue-tc` input + a `.cue-tc-capture` button BETWEEN `.cue-num` and `.cue-name`.

- [ ] **Step 5.2: Modify `renderCue` to include TC input**

In `renderCue`, find the `hdr.innerHTML = ...` template literal (lines ~198-204) and update the header markup:

```js
const tcVal = escapeHtml(cue.position || '');
const tcValid = !cue.position || isValidSmpte(cue.position);
const tcCls = tcValid ? 'cue-tc' : 'cue-tc invalid';
hdr.innerHTML = `
  <button class="chevron" title="${cue.collapsed ? 'Expand' : 'Collapse'}">${chev}</button>
  <input type="number" step="0.1" class="cue-num" value="${escapeHtml(cue.n)}" title="Cue number">
  <input type="text" class="${tcCls}" placeholder="HH:MM:SS:FF" value="${tcVal}" title="Timecode (25fps SMPTE) — empty = excluded from TC export">
  <button class="icon-btn cue-tc-capture" title="Capture from audio playhead">🎯</button>
  <input type="text" class="cue-name" placeholder="Cue name (Intro, Verse, Chorus...)" value="${escapeHtml(cue.name)}">
  ${cue.collapsed ? `<span class="cue-summary">${escapeHtml(cueSummary(cue))}</span>` : ''}
  <button class="icon-btn danger" title="Remove cue">&times;</button>`;
```

Add event handlers after the existing `numInput` handler (around line ~210-220):

```js
const tcInput = hdr.querySelector('.cue-tc');
tcInput.addEventListener('input', e => {
  cue.position = e.target.value;
  saveState();
});
tcInput.addEventListener('blur', e => {
  // Re-render to apply / clear the .invalid class — keep the value either way.
  render();
});

hdr.querySelector('.cue-tc-capture').addEventListener('click', e => {
  e.stopPropagation();
  const captured = captureCurrentPlayheadAsSmpte();
  if (!captured) { alert('Load audio first.'); return; }
  cue.position = captured;
  saveState();
  render();
});
```

- [ ] **Step 5.3: Add styles in `web/css/styles.css`**

Append at the end of the file:

```css
.cue-tc {
  width: 110px;
  font-family: 'Courier New', monospace;
  font-size: 0.85em;
  background: #2a2a2e;
  border: 1px solid #444;
  color: #e8e8e8;
  padding: 4px 6px;
  border-radius: 3px;
}
.cue-tc.invalid {
  border-color: #d63a3a;
  background: #3a1a1a;
}
.cue-tc-capture {
  font-size: 1em;
  padding: 2px 6px;
  background: transparent;
  border: 1px solid #444;
  border-radius: 3px;
  cursor: pointer;
}
.cue-tc-capture:hover { background: #333; }
```

- [ ] **Step 5.4: Manual verification (no automated test for DOM)**

Open `web/index.html` in a browser (Electron app or directly):

1. Click `+ Add Cue` — verify the new cue card shows an empty `HH:MM:SS:FF` input next to the number input
2. Type `00:00:10:00` → should accept, no red border
3. Type `bogus` and blur → input should get red border (`.invalid` class)
4. Clear the bogus value → red border removed
5. Click 🎯 with no audio loaded → alert "Load audio first."

- [ ] **Step 5.5: Commit**

```
git add web/js/render.js web/css/styles.css
git commit -m "feat(web): per-cue TC input + capture button in cue card"
```

---

## Task 6: 4 new toolbar buttons in `index.html`

**Files:**
- Modify: `web/index.html` (toolbar section, lines 49-67)
- Modify: `README.md` (1 paragraph at end)

- [ ] **Step 6.1: Add buttons to toolbar in `web/index.html`**

In the `<div id="toolbar">` section, after the `Send all → MA` button and before `Save Project`, insert:

```html
<button id="exportTc" class="ghost" title="Export TC events as .lua (paste-into-plugin)">Export TC .lua</button>
<button id="exportTcAll" class="ghost" title="Export all songs' TC events as .lua">Export all TC .lua</button>
<button id="sendTcOscCurrent" class="osc-btn" disabled title="Send TC events of current song. PRE-REQ: Track in TC pool exists.">Send TC current → MA</button>
<button id="sendTcOscAll" class="osc-btn" disabled title="Send TC events of all songs. PRE-REQ: Track in TC pool exists for each.">Send TC all → MA</button>
```

- [ ] **Step 6.2: Add pre-conditions note to `README.md`**

Open the project root `README.md`. Find an appropriate section (or add at the end before any monorepo footer):

```markdown
## Timecode show (optional)

The compiler can populate grandMA3 Timecode pools with events that fire your
song's cues. Convention: TC pool number = Sequence number.

**One-time MA3 setup per song (manual):**
1. Sequence `N` exists with cues (compiler's regular Send sequences this).
2. Timecode pool `N` exists (create it on MA3, or it will be created on first
   Send TC).
3. Track inside TC pool `N` has `target = Sequence N` — drag the sequence onto
   the TC pool slot on MA3.

**Per-cue authoring in the compiler:**
- Each cue has an `HH:MM:SS:FF` input (25 fps). Empty = excluded from TC.
- 🎯 button captures the current audio playhead.

**Send:** `Send TC current → MA` (active song) or `Send TC all → MA`. The
operation wipes existing events in the SubTrack and writes new ones from the
compiler (Overwrite-only in v1).
```

- [ ] **Step 6.3: Commit**

```
git add web/index.html README.md
git commit -m "feat(web): TC toolbar buttons + README pre-conditions note"
```

---

## Task 7: Wire OSC + export buttons in `osc.js` + `main.js`

**Files:**
- Modify: `web/js/osc.js`
- Modify: `web/js/main.js`

- [ ] **Step 7.1: Add `sendTcCurrentViaOsc` + `sendTcAllViaOsc` to `osc.js`**

Open `web/js/osc.js`. Modify `setOscState` (around lines 9-22) to also toggle the new TC buttons:

```js
function setOscState(s, label) {
  oscState = s;
  const pill = document.getElementById('oscPill');
  pill.className = 'osc-pill ' + s;
  pill.textContent = label || ({
    offline: '○ OSC offline',
    connecting: '● connecting…',
    online: '● OSC online',
    sending: '● sending…'
  })[s];
  const canSend = (s === 'online');
  document.getElementById('sendOscCurrent').disabled = !canSend;
  document.getElementById('sendOscAll').disabled = !canSend;
  document.getElementById('sendTcOscCurrent').disabled = !canSend;
  document.getElementById('sendTcOscAll').disabled = !canSend;
}
```

After `sendAllViaOsc` (around line 90), add:

```js
function sendTcCurrentViaOsc() {
  const song = activeSong();
  if (!song) return;
  const lines = buildTcCmdLines([song]);
  if (lines.length === 0) { alert('No cues with a valid TC position in the active song.'); return; }
  sendCmdLinesViaOsc(lines, `TC for "${song.name || '(untitled)'}"`);
}

function sendTcAllViaOsc() {
  const songs = state.songs.filter(s => (s.cues || []).some(c => isValidSmpte(c.position)));
  if (songs.length === 0) { alert('No songs have any cues with a valid TC position.'); return; }
  const lines = buildTcCmdLines(songs);
  sendCmdLinesViaOsc(lines, `TC for ${songs.length} song(s)`);
}
```

Add to `CC.osc` manifest at the bottom: `sendTcCurrentViaOsc, sendTcAllViaOsc`.

- [ ] **Step 7.2: Wire button events in `main.js`**

Open `web/js/main.js`. After the existing OSC button wiring (around line 114-115), add:

```js
document.getElementById('sendTcOscCurrent').addEventListener('click', sendTcCurrentViaOsc);
document.getElementById('sendTcOscAll').addEventListener('click', sendTcAllViaOsc);
document.getElementById('exportTc').addEventListener('click', exportTcLua);
document.getElementById('exportTcAll').addEventListener('click', exportAllTcLua);
```

- [ ] **Step 7.3: Manual smoke test**

1. Open the app (Electron or `web/index.html` directly with the proxy)
2. Load `examples/SONG_1.json`
3. Add a TC position to cue 1 (e.g., `00:00:05:00`) — typing should persist
4. Click `Export TC .lua` — a file `SONG_1.tc.lua` (or similar) downloads
5. Open the downloaded file in a text editor — verify it contains a `Delete Timecode 666.1.1.1.1.1 /NoConfirmation` line (or whatever the SONG_1 sequence number is) followed by a `Store Timecode ... Goto Cue 1` line
6. With OSC online: click `Send TC current → MA` — observe the OSC pill goes to "sending…" then back to "online" without errors. (We can't verify the desk side without a console.)

- [ ] **Step 7.4: Commit**

```
git add web/js/osc.js web/js/main.js
git commit -m "feat(web): wire TC send + export buttons"
```

---

## Task 8: Update `shared/ma3-command-spec.md`

**Files:**
- Modify: `shared/ma3-command-spec.md` (append at end)

- [ ] **Step 8.1: Append the new section**

Open `shared/ma3-command-spec.md` and append at the end:

```markdown
## Timecode show per song (optional)

Independent from the sequence/cue command sequence above. Driven by the
`Send TC ...` toolbar buttons and `buildTcCmdLines`/`buildTcLua`.

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
```

- [ ] **Step 8.2: Commit**

```
git add shared/ma3-command-spec.md
git commit -m "docs(spec): MA3 contract for Timecode events"
```

---

## Task 9: Golden fixture + regression test

**Files:**
- Create: `examples/SONG_1.tc.cmdlines.txt`
- Modify: `web/test/tc.test.js`

- [ ] **Step 9.1: Inspect SONG_1.json to know its sequence + cues + TC**

Read `examples/SONG_1.json` and note: the sequence number, and which cues
have a `position` field. If no cues currently have a TC, we add one as part
of this task — keeps the fixture realistic.

If SONG_1 has no cues with `position`, manually add positions to the JSON to
mirror a CuePoints CSV import (e.g., cue 1 at `00:00:05:15`, cue 2 at
`00:00:10:00`). Keep change minimal — just the `position` fields.

- [ ] **Step 9.2: Generate the golden fixture**

From the project root:

```
cd web && node -e "
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const sb = { window: { CC: {} }, console };
vm.createContext(sb);
['constants.js','util.js'].forEach(f => vm.runInContext(fs.readFileSync(path.resolve('js', f), 'utf8'), sb, { filename: f }));
sb.state = JSON.parse(fs.readFileSync(path.resolve('..', 'examples', 'SONG_1.json'), 'utf8'));
if (sb.state.songName !== undefined) {
  sb.state = { songs: [{ name: sb.state.songName, sequence: sb.state.sequence, cues: sb.state.cues }], storeMode: 'Overwrite' };
}
sb.defaults = {};
vm.runInContext(fs.readFileSync(path.resolve('js', 'compile.js'), 'utf8'), sb, { filename: 'compile.js' });
const out = sb.window.CC.compile.buildTcCmdLines(sb.state.songs);
fs.writeFileSync(path.resolve('..', 'examples', 'SONG_1.tc.cmdlines.txt'), out.join('\n') + '\n');
console.log('wrote', out.length, 'lines');
"
```

Verify `examples/SONG_1.tc.cmdlines.txt` exists, starts with 200 `Delete Timecode ...` lines, and ends with `Store ... Goto Cue ... Sequence ...` / `Set ... Property 'time' ...` pairs.

- [ ] **Step 9.3: Add regression test**

Append to `web/test/tc.test.js`:

```js
test('regression: SONG_1.json matches SONG_1.tc.cmdlines.txt golden', () => {
  const compile = loadCompile();
  const json = JSON.parse(fs.readFileSync(path.resolve(__dirname, '..', '..', 'examples', 'SONG_1.json'), 'utf8'));
  // Migrate single-song shape to multi-song if needed.
  const songs = Array.isArray(json.songs) ? json.songs
    : [{ name: json.songName || '', sequence: json.sequence, cues: json.cues }];
  const expected = fs.readFileSync(path.resolve(__dirname, '..', '..', 'examples', 'SONG_1.tc.cmdlines.txt'), 'utf8').trimEnd();
  const actual = compile.buildTcCmdLines(songs).join('\n');
  assert.strictEqual(actual, expected);
});
```

- [ ] **Step 9.4: Run, verify pass**

```
cd web && node --test test/tc.test.js
```

Expected: 10 tests passing including the new regression.

- [ ] **Step 9.5: Commit**

```
git add examples/SONG_1.json examples/SONG_1.tc.cmdlines.txt web/test/tc.test.js
git commit -m "test(web): golden fixture for SONG_1 TC commands"
```

---

## Task 10: Final integration verification

**Files:** none modified — manual UAT only.

- [ ] **Step 10.1: Spin up desktop app + onPC**

1. Start onPC on this PC (loopback target works).
2. Run `cd desktop && npm start` to launch the Electron app.
3. Confirm OSC pill goes `online` and MA3 OSC Echo Input = Yes.

- [ ] **Step 10.2: End-to-end TC flow**

1. In compiler: Load `examples/SONG_1.json`.
2. On MA3 (one-time setup for the song's sequence number, e.g. 666):
   - Run the regular `Send current → MA` first to populate Sequence 666 with cues.
   - Open the TC pool (slot 666); MA3 may auto-create it on demand or via
     interactive `Store Timecode 666`.
   - Drag Sequence 666 onto the TC pool 666 to create the Track.
3. In compiler: click `Send TC current → MA`. OSC pill goes `sending…` then
   `online`.
4. On MA3: open the TC pool 666 timeline. Confirm there are events at the
   timestamps from the cue positions, each firing the corresponding
   `Goto Cue N Sequence 666`.
5. Run the TC show → cues fire at the expected times.

- [ ] **Step 10.3: Negative path checks**

1. Add a cue with `position = 'invalid'`. Click `Send TC current → MA`. The
   cue should be skipped (no Store for it) and the others still ship. No
   browser/Electron console error.
2. Add a cue with empty `position`. Same expected behavior.
3. Use 🎯 button with no audio loaded → alert "Load audio first.".

- [ ] **Step 10.4: Final commit (CHANGELOG)**

Open `CHANGELOG.md` and add an entry under the unreleased section (or at top
if no unreleased section exists):

```markdown
- **web:** Timecode per cue — author SMPTE positions per cue and push to MA3
  Timecode pool via `Send TC current/all → MA` (Cmd-line, Overwrite-only;
  see `shared/ma3-command-spec.md` §Timecode show). Pre-condition: Track in
  TC pool created on MA3 first.
```

```
git add CHANGELOG.md
git commit -m "docs: changelog — TC per cue (v0.2)"
```

---

## Self-Review

**Spec coverage:**
- Goal/conventions/pre-conditions: documented in Task 6 (README) and Task 8 (spec).
- Data model "no new fields": confirmed — only reuses `cue.position`.
- UI (TC input + 🎯 + no-TC badge): Task 5. ⚠ The "no TC" badge mentioned in
  the spec is implicit (empty input). If a more explicit badge is wanted, add
  a follow-up after seeing the UI in action.
- Capture from playhead: Task 2.
- MA3 contract: Task 3 (Cmd-lines), Task 4 (Lua wrapper), Task 8 (spec doc).
- Compiler pipeline (Overwrite-only): Task 3, hard-coded.
- Edge cases (invalid/empty TC, no audio): Task 5 (UI) and Task 3 (filter).
- Testing strategy (golden fixture + manual UAT): Tasks 9 and 10.

**Placeholder scan:** None. Every step has either exact code or exact commands.

**Type consistency:**
- `isValidSmpte` (util) — used in Task 3 (`compile.js`) and Task 5 (`render.js`).
- `captureCurrentPlayheadAsSmpte` (audio) — used in Task 5 (`render.js`).
- `buildTcCmdLines` / `buildTcLua` / `exportTcLua` / `exportAllTcLua` — defined
  in Tasks 3-4, used in Task 7 (osc/main wiring).
- `sendTcCurrentViaOsc` / `sendTcAllViaOsc` — defined in Task 7.

All names and signatures match across tasks.

**Out of scope (per spec):** Merge for TC, multi-fire, edit-on-waveform, ≠25fps,
auto Track creation, read-back. None of these are in this plan.

---
