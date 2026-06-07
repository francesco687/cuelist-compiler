# Audio Track Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a programming-time polish pass on the per-song audio panel — real transport (prev/stop/play/next/restart), time ruler, big SMPTE TC reader, red markers + white playhead, non-destructive in/out trim.

**Architecture:** Web-only. All changes confined to `web/js/audio.js` + `web/js/state.js` (one-line migration) + `web/css/styles.css`. Pure helpers (marker search, tick picking, clamp, auto-pause predicate) extracted to the top of `audio.js` and re-exported via `window.CC.audio` so they can be unit-tested in isolation via `vm.createContext`. No DOM in helpers. No hub / OSC / iOS / Lua / shared-spec changes.

**Tech Stack:** Vanilla JS, HTML5 `<audio>`, Canvas2D for waveform + ruler, plain CSS, Node `--test` runner with `vm.createContext` for unit tests.

**Spec:** `docs/superpowers/specs/2026-06-07-audio-track-polish-design.md`. Read the "Timing semantics" section before starting — every task depends on the `songTime = currentTime − trim.startS` contract.

---

## File Map

| Path | New / Modified | Responsibility |
|---|---|---|
| `web/js/state.js` | Modified | One line in `migrateState`: inject default `audioTrim` on each song. |
| `web/js/audio.js` | Modified (bulk) | Pure helpers at top of file; transport bar markup + wiring; ruler canvas + draw fn; TC reader update; trim handle drag; auto-pause clamp; capture function adjustment; marker file-time math through `trim.startS`. |
| `web/css/styles.css` | Modified | Red marker palette, white playhead, transport row, ruler row, trim handles + dim overlay, TC reader typography. |
| `web/test/audio-helpers.test.js` | NEW | Unit tests for the pure helpers extracted from `audio.js`. |
| `web/index.html` | Untouched | Panel is fully rendered by `audio.js`. |
| `examples/SONG_1.json` | Untouched | Loads with default trim via migration. |

`compile.js`, `transport.js`, `osc.js`, OSC, Lua templates, hub, iOS, `shared/ma3-command-spec.md`, plugins: **not touched in any task**.

---

## Order of Tasks (and why)

1. **State migration first** — every later task relies on `song.audioTrim` existing.
2. **Pure helpers + their tests** — locks the math contract before any UI work.
3. **Transport bar** — smallest visible win, no trim coupling yet (uses default `{startS:0, endS:null}` and the new helpers).
4. **Marker / playhead recolour** — pure CSS, zero risk, easy to roll back.
5. **TC reader** — small DOM addition, reuses `updatePlayhead`.
6. **Ruler canvas** — independent visual layer.
7. **Trim handles + dim + auto-pause + click-clamp + capture adjustment** — the most complex change, lands last so previous tasks are stable underneath.
8. **Manual smoke + ship** — verify against `examples/SONG_1.json`.

Each numbered task ends with a green-tests gate and a commit. Branch `feature/audio-track-polish` is already created and the spec is on it (commit `453f4fa`).

---

## Task 1: Migrate `audioTrim` into every song on load

**Files:**
- Modify: `web/js/state.js` (`migrateState`, around the `s.songs.forEach(song => ...)` loop, line ~117)

- [ ] **Step 1: Add the migration line**

In `web/js/state.js`, inside `migrateState`, the existing per-song loop is:

```js
s.songs.forEach(song => {
  if (!song.id) song.id = genId();
  if (!Array.isArray(song.cues)) song.cues = [];
  if (typeof song.audioFileName !== 'string') song.audioFileName = '';
  migrateCues(song.cues);
});
```

Add one line at the end of the loop body:

```js
s.songs.forEach(song => {
  if (!song.id) song.id = genId();
  if (!Array.isArray(song.cues)) song.cues = [];
  if (typeof song.audioFileName !== 'string') song.audioFileName = '';
  if (!song.audioTrim || typeof song.audioTrim !== 'object') {
    song.audioTrim = { startS: 0, endS: null };
  } else {
    if (typeof song.audioTrim.startS !== 'number' || song.audioTrim.startS < 0) song.audioTrim.startS = 0;
    if (song.audioTrim.endS != null && typeof song.audioTrim.endS !== 'number') song.audioTrim.endS = null;
  }
  migrateCues(song.cues);
});
```

Also add `audioTrim: { startS: 0, endS: null }` to the two song-object literals in `newSong()` and `newProject()` and the placeholder in `migrateState` (the `if (s.songs.length === 0)` branch) and `importCsv` (the `state.songs.push(ns)` placeholder) and `loadProject`'s reset code:

```js
// in newSong():
return {
  id: genId(),
  name: '',
  sequence: maxSeq > 0 ? maxSeq + 1 : 1,
  cues: [],
  audioFileName: '',
  audioTrim: { startS: 0, endS: null }
};
```

```js
// in newProject():
const song = { id: genId(), name: '', sequence: 1, cues: [], audioFileName: '', audioTrim: { startS: 0, endS: null } };
```

```js
// in migrateState empty-songs branch:
const song = { id: genId(), name: '', sequence: 1, cues: [], audioFileName: '', audioTrim: { startS: 0, endS: null } };
```

```js
// in importCsv per-song push:
const song = {
  id: genId(),
  name: trackName,
  sequence,
  cues,
  audioFileName: '',
  audioTrim: { startS: 0, endS: null }
};
```

```js
// in importCsv placeholder push:
const ns = { id: genId(), name: '', sequence: 1, cues: [], audioFileName: '', audioTrim: { startS: 0, endS: null } };
```

- [ ] **Step 2: Smoke-check in browser**

Run: `start desktop\` (or `cd desktop && npm start`).
Open dev tools console, type:

```js
state.songs.map(s => s.audioTrim)
```

Expected: array with `{startS: 0, endS: null}` for every song, including SONG_1.

- [ ] **Step 3: Commit**

```bash
git add web/js/state.js
git commit -m "feat(saetta): migrate audioTrim={startS:0,endS:null} per song"
```

---

## Task 2: Extract pure helpers + write their tests

**Files:**
- Modify: `web/js/audio.js` (top of file, after the `let ...` block)
- Create: `web/test/audio-helpers.test.js`

Pure helpers, no DOM, no globals — testable in `vm.createContext`. We are pulling marker-search and trim math into named exported functions so the tests can hit them directly, before any UI is touched.

- [ ] **Step 1: Write the failing test file**

Create `web/test/audio-helpers.test.js`:

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadAudioHelpers() {
  const sandbox = { window: { CC: {} }, console };
  vm.createContext(sandbox);
  const util = fs.readFileSync(path.resolve(__dirname, '..', 'js', 'util.js'), 'utf8');
  const audio = fs.readFileSync(path.resolve(__dirname, '..', 'js', 'audio.js'), 'utf8');
  vm.runInContext(util, sandbox, { filename: 'util.js' });
  // audio.js touches DOM in some functions — stub a minimal document so the file evaluates without throwing.
  sandbox.document = { getElementById: () => null, querySelectorAll: () => [], querySelector: () => null, body: { style: {} }, createElement: () => ({ classList: { add(){}, toggle(){}, contains(){return false;} }, addEventListener(){}, appendChild(){}, style:{} }) };
  sandbox.requestAnimationFrame = () => 0;
  sandbox.cancelAnimationFrame = () => {};
  // state.js globals referenced at top level — provide stubs.
  sandbox.state = { songs: [], activeSongId: null };
  sandbox.activeSong = () => null;
  sandbox.saveState = () => {};
  sandbox.render = () => {};
  sandbox.CC = sandbox.window.CC;
  vm.runInContext(audio, sandbox, { filename: 'audio.js' });
  return sandbox.window.CC.audio;
}

test('pickTickInterval: ≤30s → 1s ticks, major every 5s', () => {
  const { pickTickInterval } = loadAudioHelpers();
  assert.deepStrictEqual(pickTickInterval(15),  { interval: 1, major: 5 });
  assert.deepStrictEqual(pickTickInterval(30),  { interval: 1, major: 5 });
});

test('pickTickInterval: ≤2min → 5s ticks, major every 30s', () => {
  const { pickTickInterval } = loadAudioHelpers();
  assert.deepStrictEqual(pickTickInterval(31),  { interval: 5, major: 30 });
  assert.deepStrictEqual(pickTickInterval(120), { interval: 5, major: 30 });
});

test('pickTickInterval: >2min → 10s ticks, major every 60s', () => {
  const { pickTickInterval } = loadAudioHelpers();
  assert.deepStrictEqual(pickTickInterval(121), { interval: 10, major: 60 });
  assert.deepStrictEqual(pickTickInterval(600), { interval: 10, major: 60 });
});

test('clampSeek: inside window passes through', () => {
  const { clampSeek } = loadAudioHelpers();
  assert.strictEqual(clampSeek(5, { startS: 1, endS: 9 }, 10), 5);
});

test('clampSeek: before startS clamps to startS', () => {
  const { clampSeek } = loadAudioHelpers();
  assert.strictEqual(clampSeek(0.5, { startS: 1, endS: 9 }, 10), 1);
});

test('clampSeek: after endS clamps to endS', () => {
  const { clampSeek } = loadAudioHelpers();
  assert.strictEqual(clampSeek(9.5, { startS: 1, endS: 9 }, 10), 9);
});

test('clampSeek: endS=null clamps to duration on the right', () => {
  const { clampSeek } = loadAudioHelpers();
  assert.strictEqual(clampSeek(15, { startS: 0, endS: null }, 10), 10);
});

test('shouldAutoPause: past endS while playing → true', () => {
  const { shouldAutoPause } = loadAudioHelpers();
  assert.strictEqual(shouldAutoPause(9.1, { startS: 0, endS: 9 }, false), true);
});

test('shouldAutoPause: at endS exactly → true', () => {
  const { shouldAutoPause } = loadAudioHelpers();
  assert.strictEqual(shouldAutoPause(9, { startS: 0, endS: 9 }, false), true);
});

test('shouldAutoPause: inside window → false', () => {
  const { shouldAutoPause } = loadAudioHelpers();
  assert.strictEqual(shouldAutoPause(5, { startS: 0, endS: 9 }, false), false);
});

test('shouldAutoPause: endS=null → false', () => {
  const { shouldAutoPause } = loadAudioHelpers();
  assert.strictEqual(shouldAutoPause(99999, { startS: 0, endS: null }, false), false);
});

test('shouldAutoPause: already paused → false (idempotent)', () => {
  const { shouldAutoPause } = loadAudioHelpers();
  assert.strictEqual(shouldAutoPause(99, { startS: 0, endS: 9 }, true), false);
});

test('fileToSongTime / songToFileTime round-trip', () => {
  const { fileToSongTime, songToFileTime } = loadAudioHelpers();
  const trim = { startS: 1.5, endS: 9 };
  assert.strictEqual(fileToSongTime(3.0, trim), 1.5);
  assert.strictEqual(songToFileTime(1.5, trim), 3.0);
  assert.strictEqual(songToFileTime(fileToSongTime(7, trim), trim), 7);
});

// Marker search — songTime is "time since in-point". cues carry SMPTE strings.
test('findPrevMarker: returns largest cue strictly before now - 0.25s tolerance', () => {
  const { findPrevMarker } = loadAudioHelpers();
  const cues = [
    { n: 1, position: '00:00:01:00' }, // 1s
    { n: 2, position: '00:00:05:00' }, // 5s
    { n: 3, position: '00:00:10:00' }  // 10s
  ];
  assert.strictEqual(findPrevMarker(7.0, cues), cues[1]);   // 5s
  assert.strictEqual(findPrevMarker(5.0, cues), cues[0]);   // sitting on 5s → previous is 1s (tolerance)
  assert.strictEqual(findPrevMarker(0.5, cues), null);      // nothing before
});

test('findNextMarker: returns smallest cue strictly after now + 0.05s tolerance', () => {
  const { findNextMarker } = loadAudioHelpers();
  const cues = [
    { n: 1, position: '00:00:01:00' },
    { n: 2, position: '00:00:05:00' },
    { n: 3, position: '00:00:10:00' }
  ];
  assert.strictEqual(findNextMarker(3.0, cues), cues[1]);   // → 5s
  assert.strictEqual(findNextMarker(5.0, cues), cues[2]);   // sitting on 5s → next is 10s
  assert.strictEqual(findNextMarker(10.0, cues), null);     // already at the last
  assert.strictEqual(findNextMarker(99.0, cues), null);     // past the last
});

test('findPrev/findNext: cues with empty or invalid position are skipped', () => {
  const { findPrevMarker, findNextMarker } = loadAudioHelpers();
  const cues = [
    { n: 1, position: '' },
    { n: 2, position: 'garbage' },
    { n: 3, position: '00:00:05:00' }
  ];
  assert.strictEqual(findPrevMarker(7, cues), cues[2]);
  assert.strictEqual(findNextMarker(0, cues), cues[2]);
});

test('findPrev/findNext: handles unsorted cue arrays', () => {
  const { findPrevMarker, findNextMarker } = loadAudioHelpers();
  const cues = [
    { n: 3, position: '00:00:10:00' },
    { n: 1, position: '00:00:01:00' },
    { n: 2, position: '00:00:05:00' }
  ];
  assert.strictEqual(findPrevMarker(7,  cues).n, 2);
  assert.strictEqual(findNextMarker(2,  cues).n, 2);
});
```

- [ ] **Step 2: Run tests, confirm they FAIL**

Run: `cd web && node --test test/audio-helpers.test.js`
Expected: failures on every test — `CC.audio.pickTickInterval is not a function`, etc.

- [ ] **Step 3: Add the helpers at the top of `audio.js`**

In `web/js/audio.js`, between line 16 (`const channelMute = ...`) and line 18 (`async function loadAudioFile`), insert:

```js
// --- Pure helpers (no DOM, no globals — unit-tested in test/audio-helpers.test.js)

function fileToSongTime(currentTime, trim) {
  return currentTime - (trim && trim.startS ? trim.startS : 0);
}

function songToFileTime(songT, trim) {
  return songT + (trim && trim.startS ? trim.startS : 0);
}

function clampSeek(rawS, trim, duration) {
  const lo = trim && typeof trim.startS === 'number' ? trim.startS : 0;
  const hi = trim && trim.endS != null ? trim.endS : duration;
  return Math.max(lo, Math.min(hi, rawS));
}

function shouldAutoPause(currentTime, trim, alreadyPaused) {
  if (alreadyPaused) return false;
  if (!trim || trim.endS == null) return false;
  return currentTime >= trim.endS;
}

function pickTickInterval(duration) {
  if (duration <= 30)  return { interval: 1,  major: 5  };
  if (duration <= 120) return { interval: 5,  major: 30 };
  return { interval: 10, major: 60 };
}

function findPrevMarker(songTime, cues) {
  const PREV_TOL = 0.25;
  let best = null, bestT = -Infinity;
  for (const c of cues) {
    const t = timecodeToSeconds(c.position);
    if (isNaN(t)) continue;
    if (t < songTime - PREV_TOL && t > bestT) { best = c; bestT = t; }
  }
  return best;
}

function findNextMarker(songTime, cues) {
  const NEXT_TOL = 0.05;
  let best = null, bestT = Infinity;
  for (const c of cues) {
    const t = timecodeToSeconds(c.position);
    if (isNaN(t)) continue;
    if (t > songTime + NEXT_TOL && t < bestT) { best = c; bestT = t; }
  }
  return best;
}
```

And at the bottom of `audio.js`, extend the public surface to expose them:

```js
window.CC = window.CC || {};
window.CC.audio = {
  loadAudioFile, setActiveAudioFromCache, setChannelMute, drawWaveform, renderAudioPanel,
  wireLoadAudio, togglePlay, startPlayheadLoop, stopPlayheadLoop, updatePlayhead,
  updateCurrentMarker, renderMarkers, captureCurrentPlayheadAsSmpte, dropMarkerAtPlayhead,
  selectMarker, deselectAllMarkers, deleteSelectedMarker, getSelectedMarkerCueN,
  // new pure helpers (test surface)
  fileToSongTime, songToFileTime, clampSeek, shouldAutoPause, pickTickInterval,
  findPrevMarker, findNextMarker
};
```

(Replace the existing single-line `window.CC.audio = { ... }` at the bottom of the file with the multi-line block above.)

- [ ] **Step 4: Run tests, confirm they PASS**

Run: `cd web && node --test test/audio-helpers.test.js`
Expected: every test passes (16 tests).

- [ ] **Step 5: Commit**

```bash
git add web/js/audio.js web/test/audio-helpers.test.js
git commit -m "feat(saetta): extract pure audio helpers + unit tests"
```

---

## Task 3: Transport bar — replace single Play/Pause with `⏮ ⏹ ⏯ ⏭ ↻`

**Files:**
- Modify: `web/js/audio.js` (`renderAudioPanel`, `togglePlay`, add new handlers)
- Modify: `web/css/styles.css` (transport button row sizing)

The trim is still `{startS:0, endS:null}` on every song (Task 1) so all transport behaviour still operates on the full file. Trim handles ship later in Task 7 and will not change any of this code because we already read from `trim` everywhere.

- [ ] **Step 1: Replace transport markup in `renderAudioPanel`**

In `web/js/audio.js`, replace the current `#audioControls` block (lines ~189-199 of the original file) with:

```js
panel.innerHTML = `
  <div id="audioControls">
    <div class="transport">
      <button id="prevBtn"    title="Previous marker">⏮</button>
      <button id="stopBtn"    title="Stop (back to in-point)">⏹</button>
      <button id="playBtn"    title="Play / Pause">${audioEl.paused ? '▶' : '⏸'}</button>
      <button id="nextBtn"    title="Next marker">⏭</button>
      <button id="restartBtn" title="Restart from in-point">↻</button>
    </div>
    ${ch >= 2 ? `
      <button class="channel-toggle ${channelMute.L ? 'muted' : 'active'}" data-ch="L" title="Toggle Left channel">L</button>
      <button class="channel-toggle ${channelMute.R ? 'muted' : 'active'}" data-ch="R" title="Toggle Right channel">R</button>
    ` : ''}
    <span class="filename" title="${escapeHtml(audioFileName)}">${escapeHtml(audioFileName)}</span>
    <span class="time" id="audioTime">0:00 / ${secondsToMMSS(dur)}</span>
    <button id="reloadAudioBtn" class="ghost" title="Load a different file">Change</button>
    <input type="file" id="loadAudio" accept="audio/*" style="display:none">
  </div>
  <div id="timeline">
    ${ch >= 2 ? `
      <div class="channel-wave"><span class="chan-label">L</span><canvas id="waveL"></canvas></div>
      <div class="channel-wave"><span class="chan-label">R</span><canvas id="waveR"></canvas></div>
    ` : `
      <div class="channel-wave" style="height:90px;"><canvas id="waveL"></canvas></div>
    `}
    <div class="markers" id="markers"></div>
    <div class="playhead" id="playhead" style="left:0px"></div>
  </div>
`;
```

(Differences vs original: `playBtn` text is just the glyph `▶` or `⏸`, no "Play"/"Pause" word; new sibling buttons; `transport` wrapper div.)

- [ ] **Step 2: Wire the new buttons**

Right after the existing `document.getElementById('playBtn').addEventListener('click', togglePlay);` line (~line 212), add:

```js
document.getElementById('prevBtn').addEventListener('click', skipPrevMarker);
document.getElementById('stopBtn').addEventListener('click', stopAudio);
document.getElementById('nextBtn').addEventListener('click', skipNextMarker);
document.getElementById('restartBtn').addEventListener('click', restartAudio);
```

- [ ] **Step 3: Add the four new transport functions**

Place these right after the existing `togglePlay()` function in `audio.js`:

```js
function stopAudio() {
  if (!audioEl) return;
  audioEl.pause();
  const song = activeSong();
  const startS = (song && song.audioTrim) ? song.audioTrim.startS : 0;
  audioEl.currentTime = startS;
  updatePlayhead();
}

function restartAudio() {
  if (!audioEl) return;
  const wasPlaying = !audioEl.paused;
  const song = activeSong();
  const startS = (song && song.audioTrim) ? song.audioTrim.startS : 0;
  audioEl.currentTime = startS;
  if (wasPlaying && audioCtx && audioCtx.state === 'suspended') audioCtx.resume();
  if (wasPlaying) audioEl.play();
  updatePlayhead();
}

function skipPrevMarker() {
  const song = activeSong();
  if (!audioEl || !song) return;
  const trim = song.audioTrim || { startS: 0, endS: null };
  const songT = fileToSongTime(audioEl.currentTime, trim);
  const target = findPrevMarker(songT, song.cues);
  if (target) {
    const tS = timecodeToSeconds(target.position);
    audioEl.currentTime = songToFileTime(tS, trim);
  } else {
    audioEl.currentTime = trim.startS;
  }
  updatePlayhead();
}

function skipNextMarker() {
  const song = activeSong();
  if (!audioEl || !song) return;
  const trim = song.audioTrim || { startS: 0, endS: null };
  const songT = fileToSongTime(audioEl.currentTime, trim);
  const target = findNextMarker(songT, song.cues);
  if (!target) return; // no-op at end
  const tS = timecodeToSeconds(target.position);
  audioEl.currentTime = songToFileTime(tS, trim);
  updatePlayhead();
}
```

- [ ] **Step 4: Update Play/Pause glyph in `togglePlay` and the playhead loop**

Replace the existing `togglePlay()` body's button-update line:

```js
// before
if (btn) btn.textContent = audioEl.paused ? '▶ Play' : '⏸ Pause';
// after
if (btn) btn.textContent = audioEl.paused ? '▶' : '⏸';
```

And in `startPlayheadLoop`:

```js
// before
if (btn) btn.textContent = '⏸ Pause';
// after
if (btn) btn.textContent = '⏸';
```

And in `stopPlayheadLoop`:

```js
// before
if (btn) btn.textContent = '▶ Play';
// after
if (btn) btn.textContent = '▶';
```

- [ ] **Step 5: Add `stopAudio`, `restartAudio`, `skipPrevMarker`, `skipNextMarker` to the public surface**

In the `window.CC.audio = { ... }` block at the bottom, extend:

```js
window.CC.audio = {
  loadAudioFile, setActiveAudioFromCache, setChannelMute, drawWaveform, renderAudioPanel,
  wireLoadAudio, togglePlay, stopAudio, restartAudio, skipPrevMarker, skipNextMarker,
  startPlayheadLoop, stopPlayheadLoop, updatePlayhead,
  updateCurrentMarker, renderMarkers, captureCurrentPlayheadAsSmpte, dropMarkerAtPlayhead,
  selectMarker, deselectAllMarkers, deleteSelectedMarker, getSelectedMarkerCueN,
  fileToSongTime, songToFileTime, clampSeek, shouldAutoPause, pickTickInterval,
  findPrevMarker, findNextMarker
};
```

- [ ] **Step 6: CSS — transport row sizing**

In `web/css/styles.css`, replace the existing `#playBtn { min-width: 70px; }` rule with:

```css
#audioControls .transport {
  display: inline-flex;
  gap: 2px;
}
#audioControls .transport button {
  min-width: 36px;
  padding: 4px 8px;
  font-size: 14px;
  line-height: 1;
  background: #2a2a2e;
  border: 1px solid #444;
  color: #ddd;
  border-radius: 3px;
  cursor: pointer;
}
#audioControls .transport button:hover {
  background: #353539;
  border-color: #555;
  color: #fff;
}
#audioControls .transport button:active {
  background: #1f1f23;
}
#playBtn {
  min-width: 44px !important;
  background: #2c5e3e !important;
  border-color: #3da668 !important;
  color: #fff !important;
}
```

- [ ] **Step 7: Smoke test — desktop app**

Run: `cd desktop && npm start` (or refresh the existing window).
Load `examples/SONG_1.json` + its audio.
Verify:
- Five buttons render in the row, Play is green-highlighted.
- ⏯ toggles play/pause (no text change anymore — just glyph).
- ⏹ pauses + cursor jumps to 0:00.
- ↻ during playback: cursor jumps to 0, keeps playing.
- ⏭ from start cycles through SONG_1 markers (00:05:15, 00:10:00). Past last → no-op.
- ⏮ at end: walks back through markers. Before first → seeks to 0.

- [ ] **Step 8: Run unit tests, still green**

Run: `cd web && node --test test/audio-helpers.test.js test/tc.test.js test/transport.test.js`
Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add web/js/audio.js web/css/styles.css
git commit -m "feat(saetta): full transport bar (prev/stop/play/next/restart)"
```

---

## Task 4: Red markers + white playhead

**Files:**
- Modify: `web/css/styles.css` (marker + playhead rules around lines 661-714)

Pure CSS, no JS. We are not adding a new colour palette token — we are recolouring the existing classes in place.

- [ ] **Step 1: Replace the marker + playhead CSS block**

In `web/css/styles.css`, replace this whole block (lines ~661-714):

```css
#timeline .playhead {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 2px;
  background: #ff5a5a;
  pointer-events: none;
  z-index: 5;
  transform: translateX(-1px);
}
#timeline .markers {
  position: absolute;
  inset: 0;
  pointer-events: none;
  z-index: 4;
}
#timeline .marker {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 1px;
  background: rgba(255, 200, 50, 0.5);
  pointer-events: auto;
  cursor: pointer;
}
#timeline .marker:hover { background: rgba(255, 200, 50, 1); width: 2px; }
#timeline .marker { cursor: grab; }
#timeline .marker.selected {
  background: rgba(255, 200, 50, 1);
  width: 3px;
  box-shadow: 0 0 4px rgba(255, 200, 50, 0.8);
}
#timeline .marker.selected .marker-label {
  color: #111;
  background: rgba(255, 200, 50, 0.9);
}
#timeline .marker.current {
  background: rgba(91, 141, 214, 1);
  width: 2px;
}
#timeline .marker .marker-label {
  position: absolute;
  top: 2px;
  left: 3px;
  font-size: 0.65em;
  color: #f0c84a;
  font-weight: 600;
  white-space: nowrap;
  background: rgba(20, 20, 24, 0.7);
```

with:

```css
#timeline .playhead {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 2px;
  background: #f8f8f8;
  pointer-events: none;
  z-index: 5;
  transform: translateX(-1px);
  box-shadow: 0 0 3px rgba(0, 0, 0, 0.6);
}
#timeline .markers {
  position: absolute;
  inset: 0;
  pointer-events: none;
  z-index: 4;
}
#timeline .marker {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 1px;
  background: rgba(220, 60, 60, 0.55);
  pointer-events: auto;
  cursor: grab;
}
#timeline .marker:hover {
  background: rgba(255, 80, 80, 1);
  width: 2px;
}
#timeline .marker.selected {
  background: #ff5050;
  width: 3px;
  box-shadow: 0 0 4px rgba(255, 80, 80, 0.8);
}
#timeline .marker.selected .marker-label {
  color: #fff;
  background: rgba(180, 40, 40, 0.95);
}
#timeline .marker.current {
  background: #ff5050;
  width: 2px;
  border-left: 2px solid #fff;
}
#timeline .marker .marker-label {
  position: absolute;
  top: 2px;
  left: 3px;
  font-size: 0.65em;
  color: #fff;
  font-weight: 600;
  white-space: nowrap;
  background: rgba(120, 30, 30, 0.85);
```

(Note: leave the rest of the `.marker .marker-label` rule — the `padding`, `border-radius`, etc. — exactly as-is. Only the first lines and the surrounding rules change. Match line-by-line against the original to ensure no closing brace is lost.)

Then immediately below, find this rule:

```css
#timeline .marker.current .marker-label { color: #fff; background: rgba(61, 110, 198, 0.9); }
```

Replace with:

```css
#timeline .marker.current .marker-label { color: #fff; background: rgba(220, 60, 60, 0.95); }
```

- [ ] **Step 2: Smoke test**

Reload desktop app. Load SONG_1.json + audio. Verify:
- Markers are dark red, not gold.
- Hover → solid bright red.
- Playhead is white, with subtle dark halo for readability over a red marker.
- "Current" marker (the most recent past) is bright red with a white left border.
- Marker labels are white-on-dark-red.

- [ ] **Step 3: Commit**

```bash
git add web/css/styles.css
git commit -m "style(saetta): red markers + white playhead"
```

---

## Task 5: Big SMPTE TC reader

**Files:**
- Modify: `web/js/audio.js` (`renderAudioPanel` markup, `updatePlayhead`)
- Modify: `web/css/styles.css` (TC reader typography)

- [ ] **Step 1: Replace the single `#audioTime` span in `renderAudioPanel`**

In `web/js/audio.js`, inside the `panel.innerHTML = ...` from Task 3, replace this single line:

```html
<span class="time" id="audioTime">0:00 / ${secondsToMMSS(dur)}</span>
```

with:

```html
<div class="tc-reader">
  <span id="tcReader">00:00:00:00</span>
  <span id="tcReaderSub">0:00 / ${secondsToMMSS(dur)}</span>
</div>
```

- [ ] **Step 2: Update `updatePlayhead` to drive both readouts**

Replace the body of `updatePlayhead` with:

```js
function updatePlayhead() {
  if (!audioEl || !audioBuffer) return;
  const tl = document.getElementById('timeline');
  const ph = document.getElementById('playhead');
  const tcEl = document.getElementById('tcReader');
  const subEl = document.getElementById('tcReaderSub');
  if (!tl || !ph) return;
  const song = activeSong();
  const trim = (song && song.audioTrim) ? song.audioTrim : { startS: 0, endS: null };
  const dur = audioBuffer.duration;
  const t = audioEl.currentTime;
  const pct = dur > 0 ? t / dur : 0;
  ph.style.left = (pct * tl.clientWidth) + 'px';

  if (tcEl) {
    const songT = fileToSongTime(t, trim);
    tcEl.textContent = secondsToTimecode(Math.max(0, songT));
    tcEl.style.color =
      t < trim.startS ? '#888' :
      (trim.endS != null && t > trim.endS) ? '#ff5a5a' :
      '#fff';
  }
  if (subEl) {
    const songT = fileToSongTime(t, trim);
    const segDur = (trim.endS != null ? trim.endS : dur) - trim.startS;
    subEl.textContent = `${secondsToMMSS(Math.max(0, songT))} / ${secondsToMMSS(Math.max(0, segDur))}`;
  }
  updateCurrentMarker(t);
}
```

- [ ] **Step 3: Add the TC reader CSS**

In `web/css/styles.css`, replace the existing `#audioControls .time` rule:

```css
#audioControls .time {
  color: #ccc;
  font-size: 0.85em;
  font-family: ui-monospace, 'Consolas', monospace;
  min-width: 95px;
  text-align: right;
}
```

with:

```css
#audioControls .tc-reader {
  display: inline-flex;
  flex-direction: column;
  align-items: flex-end;
  margin-left: auto;
  padding-left: 8px;
  min-width: 130px;
  text-align: right;
  line-height: 1.1;
}
#audioControls .tc-reader #tcReader {
  font-family: ui-monospace, 'Consolas', monospace;
  font-size: 22px;
  font-weight: 700;
  color: #fff;
  letter-spacing: 0.5px;
}
#audioControls .tc-reader #tcReaderSub {
  font-family: ui-monospace, 'Consolas', monospace;
  font-size: 11px;
  color: #888;
  margin-top: 2px;
}
```

- [ ] **Step 4: Smoke test**

Reload. Load SONG_1 + audio. Verify:
- Big white `00:00:00:00` in the top-right of the control row.
- Small grey `0:00 / 3:24` (or whatever duration) below it.
- During play: SMPTE updates per frame.
- Press 🎯 (existing button in the cue editor): the captured SMPTE matches what the big readout shows at the moment of the press.

- [ ] **Step 5: Commit**

```bash
git add web/js/audio.js web/css/styles.css
git commit -m "feat(saetta): big SMPTE TC reader anchored to in-point"
```

---

## Task 6: Ruler canvas above waveform

**Files:**
- Modify: `web/js/audio.js` (`renderAudioPanel` markup, add `drawRuler` fn, hook into the resize / song-swap path)
- Modify: `web/css/styles.css` (ruler row)

- [ ] **Step 1: Add ruler canvas to the timeline markup**

In `renderAudioPanel`'s `panel.innerHTML`, change the `#timeline` block so the ruler canvas is the FIRST child:

```js
<div id="timeline">
  <canvas id="ruler"></canvas>
  ${ch >= 2 ? `
    <div class="channel-wave"><span class="chan-label">L</span><canvas id="waveL"></canvas></div>
    <div class="channel-wave"><span class="chan-label">R</span><canvas id="waveR"></canvas></div>
  ` : `
    <div class="channel-wave" style="height:90px;"><canvas id="waveL"></canvas></div>
  `}
  <div class="markers" id="markers"></div>
  <div class="playhead" id="playhead" style="left:0px"></div>
</div>
```

- [ ] **Step 2: Add the `drawRuler` function**

After `drawWaveform` in `audio.js`:

```js
function drawRuler(canvas, duration, trim) {
  if (!canvas || !duration) return;
  const dpr = window.devicePixelRatio || 1;
  const w = canvas.clientWidth, h = canvas.clientHeight;
  canvas.width = Math.max(1, Math.floor(w * dpr));
  canvas.height = Math.max(1, Math.floor(h * dpr));
  const ctx = canvas.getContext('2d');
  ctx.scale(dpr, dpr);
  ctx.clearRect(0, 0, w, h);

  const { interval, major } = pickTickInterval(duration);
  ctx.font = '10px ui-monospace, Consolas, monospace';
  ctx.textBaseline = 'alphabetic';
  const startS = trim ? trim.startS : 0;
  const endS = trim && trim.endS != null ? trim.endS : duration;

  for (let t = 0; t <= duration; t += interval) {
    const x = Math.round((t / duration) * w) + 0.5; // crisp 1-px lines
    const isMajor = (Math.round(t) % major) === 0;
    const inWindow = t >= startS && t <= endS;
    const tickColour = inWindow ? '#888' : '#333';
    const labelColour = inWindow ? '#aaa' : '#444';
    ctx.strokeStyle = tickColour;
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, isMajor ? 10 : 6);
    ctx.stroke();
    if (isMajor) {
      ctx.fillStyle = labelColour;
      // Format compact: 0:05, 1:30
      const mins = Math.floor(t / 60);
      const secs = Math.floor(t % 60);
      const label = `${mins}:${secs.toString().padStart(2, '0')}`;
      ctx.fillText(label, x + 3, h - 3);
    }
  }
}
```

- [ ] **Step 3: Call `drawRuler` from the existing render path**

Inside `renderAudioPanel`'s closing `requestAnimationFrame(() => { ... })`, add the ruler draw alongside the waveforms:

```js
requestAnimationFrame(() => {
  const ruler = document.getElementById('ruler');
  const song = activeSong();
  const trim = (song && song.audioTrim) ? song.audioTrim : { startS: 0, endS: null };
  if (ruler) drawRuler(ruler, audioBuffer.duration, trim);

  const waveL = document.getElementById('waveL');
  if (waveL) drawWaveform(waveL, audioBuffer.getChannelData(0));
  if (ch >= 2) {
    const waveR = document.getElementById('waveR');
    if (waveR) drawWaveform(waveR, audioBuffer.getChannelData(1));
  }
  renderMarkers();
  updatePlayhead();
});
```

- [ ] **Step 4: Add a ResizeObserver so the ruler redraws on window resize**

At the top of `audio.js` near the module-level state, add:

```js
let resizeObserver = null;
```

In `renderAudioPanel`, after the `requestAnimationFrame` block, add:

```js
// Re-draw ruler + waveforms when the panel is resized (window or sidebar drag).
const tlEl = document.getElementById('timeline');
if (resizeObserver) resizeObserver.disconnect();
if (window.ResizeObserver && tlEl) {
  resizeObserver = new ResizeObserver(() => {
    const ruler2 = document.getElementById('ruler');
    const song2 = activeSong();
    const trim2 = (song2 && song2.audioTrim) ? song2.audioTrim : { startS: 0, endS: null };
    if (ruler2 && audioBuffer) drawRuler(ruler2, audioBuffer.duration, trim2);
    const wl = document.getElementById('waveL');
    if (wl && audioBuffer) drawWaveform(wl, audioBuffer.getChannelData(0));
    if (audioBuffer && audioBuffer.numberOfChannels >= 2) {
      const wr = document.getElementById('waveR');
      if (wr) drawWaveform(wr, audioBuffer.getChannelData(1));
    }
    updatePlayhead();
  });
  resizeObserver.observe(tlEl);
}
```

- [ ] **Step 5: CSS — ruler row + timeline gets explicit stacking**

In `web/css/styles.css`, add right above the `#timeline canvas` rule:

```css
#timeline canvas#ruler {
  display: block;
  width: 100%;
  height: 18px;
  background: #131316;
  border-bottom: 1px solid #2a2a2e;
}
```

And change the `#timeline canvas` rule to be more specific so it does not capture the ruler:

```css
/* before */
#timeline canvas {
  display: block;
  width: 100%;
  height: 100%;
}
/* after */
#timeline .channel-wave canvas {
  display: block;
  width: 100%;
  height: 100%;
}
```

- [ ] **Step 6: Smoke test**

Reload. Load SONG_1 + audio.
Verify:
- A thin grey-on-black ruler row appears above the waveforms.
- Tick marks at sensible intervals; major ticks labeled `0:00`, `0:05`, etc.
- Resize the window: ruler redraws to fit.
- Switch songs: ruler redraws (different duration → different tick interval).

- [ ] **Step 7: Commit**

```bash
git add web/js/audio.js web/css/styles.css
git commit -m "feat(saetta): time-ruler above waveform with adaptive tick density"
```

---

## Task 7: Non-destructive trim — handles, dim overlay, auto-pause, click-clamp, capture adjustment

This is the biggest task. It adds visible state (the two handles + the dim overlay), modifies the playback loop (auto-pause + clamp click), and shifts the marker rendering math through `songToFileTime`. Because every helper was already extracted and tested in Task 2, the diff here is mostly wiring.

**Files:**
- Modify: `web/js/audio.js`
- Modify: `web/css/styles.css`

- [ ] **Step 1: Render trim handles + dim overlays in the timeline markup**

In `renderAudioPanel`, extend the `#timeline` block (built up since Task 6) to include the new layers:

```js
<div id="timeline">
  <canvas id="ruler"></canvas>
  ${ch >= 2 ? `
    <div class="channel-wave"><span class="chan-label">L</span><canvas id="waveL"></canvas></div>
    <div class="channel-wave"><span class="chan-label">R</span><canvas id="waveR"></canvas></div>
  ` : `
    <div class="channel-wave" style="height:90px;"><canvas id="waveL"></canvas></div>
  `}
  <div class="trim-dim left"  id="trimDimLeft"></div>
  <div class="trim-dim right" id="trimDimRight"></div>
  <div class="markers" id="markers"></div>
  <div class="playhead" id="playhead" style="left:0px"></div>
  <div class="trim-handle left"  id="trimHandleLeft"  title="In point — drag to set song start"></div>
  <div class="trim-handle right" id="trimHandleRight" title="Out point — drag to set song end"></div>
</div>
```

- [ ] **Step 2: Add `updateTrimVisual()` and call it from the existing render path**

After `renderMarkers` in `audio.js`:

```js
function updateTrimVisual() {
  const song = activeSong();
  if (!song || !audioBuffer) return;
  const trim = song.audioTrim || { startS: 0, endS: null };
  const dur = audioBuffer.duration;
  if (!dur) return;
  const leftPct  = (trim.startS / dur) * 100;
  const rightPct = ((trim.endS != null ? trim.endS : dur) / dur) * 100;

  const dimL = document.getElementById('trimDimLeft');
  const dimR = document.getElementById('trimDimRight');
  if (dimL) {
    dimL.style.left  = '0';
    dimL.style.width = leftPct + '%';
    dimL.style.display = leftPct > 0 ? 'block' : 'none';
  }
  if (dimR) {
    dimR.style.left  = rightPct + '%';
    dimR.style.width = (100 - rightPct) + '%';
    dimR.style.display = rightPct < 100 ? 'block' : 'none';
  }
  const hL = document.getElementById('trimHandleLeft');
  const hR = document.getElementById('trimHandleRight');
  if (hL) hL.style.left = leftPct + '%';
  if (hR) hR.style.left = rightPct + '%';
}
```

Inside the `requestAnimationFrame` block of `renderAudioPanel`, call it after `renderMarkers`:

```js
renderMarkers();
updateTrimVisual();
updatePlayhead();
```

And inside the `ResizeObserver` callback, add `updateTrimVisual()` after the wave redraws.

- [ ] **Step 3: Shift marker rendering through `songToFileTime`**

In `renderMarkers`, replace the existing per-cue position calc:

```js
// before
song.cues.forEach(cue => {
  const s = timecodeToSeconds(cue.position);
  if (isNaN(s)) return;
  const pct = s / dur;
  ...
});
```

with:

```js
const trim = song.audioTrim || { startS: 0, endS: null };
song.cues.forEach(cue => {
  const sSong = timecodeToSeconds(cue.position);
  if (isNaN(sSong)) return;
  const sFile = songToFileTime(sSong, trim);
  const pct = sFile / dur;
  if (pct < 0 || pct > 1) return;
  ...
});
```

And inside the per-marker `click` handler, replace `audioEl.currentTime = s;` with `audioEl.currentTime = sFile;`.

- [ ] **Step 4: Adjust `captureCurrentPlayheadAsSmpte`**

Replace:

```js
function captureCurrentPlayheadAsSmpte() {
  if (!audioEl || isNaN(audioEl.currentTime)) return null;
  return secondsToTimecode(audioEl.currentTime);
}
```

with:

```js
function captureCurrentPlayheadAsSmpte() {
  if (!audioEl || isNaN(audioEl.currentTime)) return null;
  const song = activeSong();
  const trim = (song && song.audioTrim) ? song.audioTrim : { startS: 0, endS: null };
  return secondsToTimecode(Math.max(0, fileToSongTime(audioEl.currentTime, trim)));
}
```

- [ ] **Step 5: Auto-pause on out-point + click-clamp**

In `updatePlayhead`, at the very top of the function body (before any DOM lookup), add the auto-pause check:

```js
function updatePlayhead() {
  if (!audioEl || !audioBuffer) return;
  const song = activeSong();
  const trim = (song && song.audioTrim) ? song.audioTrim : { startS: 0, endS: null };

  if (shouldAutoPause(audioEl.currentTime, trim, audioEl.paused)) {
    audioEl.pause();
    audioEl.currentTime = trim.endS;
  }
  // ... rest of the function (existing tc reader / playhead / sub / updateCurrentMarker)
}
```

(Make sure the `const trim = ...` from Task 5 isn't duplicated — there should be exactly one.)

In the click-to-seek handler from the existing `renderAudioPanel` (the listener on `tl`), replace:

```js
tl.addEventListener('click', e => {
  if (e.target.classList.contains('marker') || e.target.classList.contains('marker-label')) return;
  deselectAllMarkers();
  const rect = tl.getBoundingClientRect();
  const pct = (e.clientX - rect.left) / rect.width;
  audioEl.currentTime = Math.max(0, Math.min(dur, pct * dur));
  updatePlayhead();
});
```

with:

```js
tl.addEventListener('click', e => {
  if (e.target.classList.contains('marker') || e.target.classList.contains('marker-label')) return;
  if (e.target.classList.contains('trim-handle')) return;
  deselectAllMarkers();
  const rect = tl.getBoundingClientRect();
  const pct = (e.clientX - rect.left) / rect.width;
  const song = activeSong();
  const trim = (song && song.audioTrim) ? song.audioTrim : { startS: 0, endS: null };
  audioEl.currentTime = clampSeek(pct * dur, trim, dur);
  updatePlayhead();
});
```

- [ ] **Step 6: Trim handle drag**

Add at module level near `markerDragState`:

```js
let trimDragState = null; // { side: 'left'|'right', timelineRect, durationS } during a drag, else null
```

Add the drag wiring inside `renderAudioPanel` right after `panel.querySelectorAll('.channel-toggle').forEach(...)`:

```js
const hL = document.getElementById('trimHandleLeft');
const hR = document.getElementById('trimHandleRight');
if (hL) {
  hL.addEventListener('mousedown', e => startTrimDrag('left', e));
  hL.addEventListener('dblclick', () => resetTrimSide('left'));
}
if (hR) {
  hR.addEventListener('mousedown', e => startTrimDrag('right', e));
  hR.addEventListener('dblclick', () => resetTrimSide('right'));
}
```

Then add these new functions near the marker drag functions:

```js
function startTrimDrag(side, evt) {
  if (!audioBuffer) return;
  const tl = document.getElementById('timeline');
  if (!tl) return;
  evt.preventDefault();
  evt.stopPropagation();
  trimDragState = {
    side,
    timelineRect: tl.getBoundingClientRect(),
    durationS: audioBuffer.duration
  };
  document.body.style.cursor = 'ew-resize';
  window.addEventListener('mousemove', onTrimDragMove);
  window.addEventListener('mouseup', onTrimDragEnd);
}

function onTrimDragMove(evt) {
  if (!trimDragState) return;
  const song = activeSong();
  if (!song) return;
  if (!song.audioTrim) song.audioTrim = { startS: 0, endS: null };
  const trim = song.audioTrim;
  const { side, timelineRect, durationS } = trimDragState;
  let pct = (evt.clientX - timelineRect.left) / timelineRect.width;
  pct = Math.max(0, Math.min(1, pct));
  const t = pct * durationS;
  if (side === 'left') {
    const rightBound = (trim.endS != null ? trim.endS : durationS) - 1.0;
    trim.startS = Math.max(0, Math.min(rightBound, t));
  } else {
    const leftBound = trim.startS + 1.0;
    trim.endS = Math.max(leftBound, Math.min(durationS, t));
  }
  // Live redraw — cheap because handles/dim/markers are CSS-positioned.
  updateTrimVisual();
  renderMarkers();
  const ruler = document.getElementById('ruler');
  if (ruler) drawRuler(ruler, durationS, trim);
  updatePlayhead();
}

function onTrimDragEnd() {
  if (!trimDragState) return;
  trimDragState = null;
  document.body.style.cursor = '';
  window.removeEventListener('mousemove', onTrimDragMove);
  window.removeEventListener('mouseup', onTrimDragEnd);
  saveState();
}

function resetTrimSide(side) {
  const song = activeSong();
  if (!song) return;
  if (!song.audioTrim) song.audioTrim = { startS: 0, endS: null };
  if (side === 'left')  song.audioTrim.startS = 0;
  if (side === 'right') song.audioTrim.endS = null;
  updateTrimVisual();
  renderMarkers();
  const ruler = document.getElementById('ruler');
  if (ruler && audioBuffer) drawRuler(ruler, audioBuffer.duration, song.audioTrim);
  updatePlayhead();
  saveState();
}
```

- [ ] **Step 7: CSS — handles + dim overlay**

In `web/css/styles.css`, add at the end of the audio-panel section (after the ruler CSS from Task 6):

```css
#timeline .trim-dim {
  position: absolute;
  top: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.6);
  pointer-events: none;
  z-index: 3;
}
#timeline .trim-handle {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 8px;
  transform: translateX(-4px);
  background: transparent;
  border-left: 2px solid #f8f8f8;
  cursor: ew-resize;
  z-index: 6;
}
#timeline .trim-handle.right {
  border-left: none;
  border-right: 2px solid #f8f8f8;
  transform: translateX(-4px);
}
#timeline .trim-handle::after {
  content: '';
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  width: 6px;
  height: 16px;
  background: #f8f8f8;
  border-radius: 2px;
  opacity: 0.85;
}
#timeline .trim-handle:hover::after { opacity: 1; }
```

- [ ] **Step 8: Run all unit tests, still green**

Run: `cd web && node --test test/audio-helpers.test.js test/tc.test.js test/transport.test.js`
Expected: all green.

- [ ] **Step 9: Smoke test (full feature)**

Reload desktop app. Load SONG_1.json + its audio.
Verify, in order:
1. Two white handles at the timeline edges (left at 0%, right at 100%).
2. Drag the left handle to ~10% of the width. The dim overlay shades the left region. Existing markers slide right (because their file-time = `startS + smpteSeconds`). The ruler labels in the dim region go darker. The TC reader shows negative→zero behaviour as the playhead crosses the in-point.
3. Drag the right handle inward. Dim shades the right region. Play through: at `endS`, playback auto-pauses and the playhead clamps.
4. Press 🎯 in a cue editor with the playhead between in/out: the captured SMPTE equals the big TC reader value (matching is exact).
5. Double-click a handle: it snaps back to its edge (0 or duration).
6. Click on the timeline outside the trim window: cursor jumps to the nearest edge of the window, not the click point.
7. Press ⏹: cursor goes to `startS`, not 0. ↻ same.
8. Press ⏭ inside the trim window: skips between markers. Markers outside the window are still drawn but skip-next/prev ignores them only if their file-time is outside `[startS, endS]` — re-verify after dragging the in-point past a marker.
9. Reload page → trim values persist (check `state.songs[0].audioTrim` in dev tools).
10. Switch songs → handles reset to that song's stored values.

- [ ] **Step 10: Filter cues by trim window in `findPrev/findNext` (gotcha fix)**

The spec says skip-prev/next must consider cues "filtered to those whose file-time falls inside `[trim.startS, trim.endS or duration]`". The helpers only see `cues` and `songTime`, no trim. Update the callers in `skipPrevMarker` / `skipNextMarker` (added in Task 3) to pre-filter:

```js
function skipPrevMarker() {
  const song = activeSong();
  if (!audioEl || !song) return;
  const trim = song.audioTrim || { startS: 0, endS: null };
  const dur = audioBuffer ? audioBuffer.duration : Infinity;
  const endS = trim.endS != null ? trim.endS : dur;
  const inWindow = song.cues.filter(c => {
    const sSong = timecodeToSeconds(c.position);
    if (isNaN(sSong)) return false;
    const sFile = songToFileTime(sSong, trim);
    return sFile >= trim.startS && sFile <= endS;
  });
  const songT = fileToSongTime(audioEl.currentTime, trim);
  const target = findPrevMarker(songT, inWindow);
  if (target) {
    audioEl.currentTime = songToFileTime(timecodeToSeconds(target.position), trim);
  } else {
    audioEl.currentTime = trim.startS;
  }
  updatePlayhead();
}

function skipNextMarker() {
  const song = activeSong();
  if (!audioEl || !song) return;
  const trim = song.audioTrim || { startS: 0, endS: null };
  const dur = audioBuffer ? audioBuffer.duration : Infinity;
  const endS = trim.endS != null ? trim.endS : dur;
  const inWindow = song.cues.filter(c => {
    const sSong = timecodeToSeconds(c.position);
    if (isNaN(sSong)) return false;
    const sFile = songToFileTime(sSong, trim);
    return sFile >= trim.startS && sFile <= endS;
  });
  const songT = fileToSongTime(audioEl.currentTime, trim);
  const target = findNextMarker(songT, inWindow);
  if (!target) return;
  audioEl.currentTime = songToFileTime(timecodeToSeconds(target.position), trim);
  updatePlayhead();
}
```

(Re-test smoke #8 from Step 9 with this change.)

- [ ] **Step 11: Commit**

```bash
git add web/js/audio.js web/css/styles.css
git commit -m "feat(saetta): non-destructive in/out trim with auto-pause + dim overlay"
```

---

## Task 8: Manual ship verification + PR

- [ ] **Step 1: Run the full test suite**

Run: `cd web && node --test test/`
Expected: every test file green (helpers + tc + transport + any others).

- [ ] **Step 2: Test against `examples/SONG_1.json` end-to-end**

- Load project (Load Project → `examples/SONG_1.json`)
- Load its `.mp3` reference (re-select if prompted — audio is session-only)
- Walk the smoke matrix from Task 7 Step 9 once more
- Press `Export current .lua` and `Send current → MA` — verify the output is unchanged from before the polish (trim is web-only state; Lua/OSC paths must not reference `audioTrim`)

Spot-check by `grep -n audioTrim web/js/compile.js` → expected: zero hits. If non-zero, that's a bug (compile.js must not know about audioTrim).

- [ ] **Step 3: Verify backwards compatibility**

Manually edit `localStorage` (dev tools → Application → Local Storage) to remove `audioTrim` from one of the songs in `cuelistCompilerProject`. Reload the page. Verify the migration injects defaults and the panel renders normally (no console errors).

- [ ] **Step 4: Push branch + open PR**

```bash
git push -u origin feature/audio-track-polish
gh pr create --title "feat(saetta): audio track polish — transport, ruler, TC reader, red markers, trim" --body "$(cat <<'EOF'
## Summary
- Full transport bar (⏮ ⏹ ⏯ ⏭ ↻) replaces single Play/Pause
- Time ruler above waveform with adaptive tick density (1s / 5s / 10s by duration)
- Big SMPTE TC reader anchored to in-point — matches what 🎯 captures
- Red markers + white playhead (was gold + red, blurred into waveform)
- Non-destructive in/out trim: two draggable handles, dim overlay, auto-pause at out-point, click-clamp

Web-only. No hub / OSC / iOS / Lua / shared-spec changes. Lua + OSC paths still emit identical command strings (grep confirms `audioTrim` does not leak into `compile.js`).

## Test plan
- [x] Pure helpers: 16 unit tests under `web/test/audio-helpers.test.js`
- [x] Smoke: load SONG_1.json, walk transport + trim matrix per plan Task 7 Step 9
- [x] Backwards-compat: removed `audioTrim` from localStorage, migration injects defaults
- [x] Regression: `Export current .lua` output unchanged

Plan: `docs/superpowers/plans/2026-06-07-audio-track-polish.md`
Spec: `docs/superpowers/specs/2026-06-07-audio-track-polish-design.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Commit any uncommitted plan file changes (if the plan was tweaked during execution)**

```bash
git status
# if plan is modified:
git add docs/superpowers/plans/2026-06-07-audio-track-polish.md
git commit -m "docs(saetta): minor plan fixups during execution"
git push
```

---

## Self-Review Checklist

This block stays in the plan for the executor to confirm before declaring done:

- [ ] All 5 features visible in the panel
- [ ] `audio-helpers.test.js` passes (16/16)
- [ ] `compile.js` has zero references to `audioTrim` (`grep` confirms)
- [ ] `examples/SONG_1.json` loads cleanly + plays + exports identical Lua to pre-change
- [ ] Trim persists across reload
- [ ] `iOS/` directory and `shared/ma3-command-spec.md` untouched
