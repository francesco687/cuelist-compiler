# Marker-driven cue authoring — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Press `M` (in playback or paused) to drop a marker at the audio playhead, creating a new cue with `position` set to the current TC; drag the pin to nudge, click + Delete to remove. Cues are re-sorted by TC and renumbered `n = 1..N` after every change.

**Architecture:** Two pure helpers in `state.js` handle data (`appendCueWithTcAndResort`, `resortAndRenumber`) operating on a passed `song` object. `audio.js` owns marker UI (selection state, drag, drop). `main.js` adds a global `keydown` listener that respects text-input focus. Renderer needs no change because cue rows are rebuilt from `state` on `render()`.

**Tech Stack:** Vanilla JS modules loaded into `web/index.html` (no bundler), `node:test` unit tests using `vm.runInContext` (see `web/test/tc.test.js` for the pattern).

**Spec:** `docs/superpowers/specs/2026-06-06-marker-driven-cue-authoring-design.md`

---

## File map

| File | Action | Responsibility |
|---|---|---|
| `web/js/state.js` | Modify | Add `appendCueWithTcAndResort(song, tc)` and `resortAndRenumber(song)`. Export on `CC.state`. |
| `web/test/marker.test.js` | Create | Unit tests for both helpers. |
| `web/js/audio.js` | Modify | Add `dropMarkerAtPlayhead`, `selectMarker`, `deselectAllMarkers`, `deleteSelectedMarker`, `startMarkerDrag`. Update `renderMarkers` (selection class + mousedown/click handlers) and the timeline click handler (deselect on click outside marker). Export new functions on `CC.audio`. |
| `web/css/styles.css` | Modify | Add `.marker.selected` highlight and `cursor: grab` / `grabbing` rules. |
| `web/js/main.js` | Modify | New global `keydown` listener for `m`/`M` (drop) and `Delete`/`Backspace` (delete selected marker), skipping text-input focus. |

---

## Task 1: state helpers (TDD)

**Files:**
- Create: `web/test/marker.test.js`
- Modify: `web/js/state.js` (add two functions, extend `CC.state` export)

- [ ] **Step 1: Write the failing tests**

Create `web/test/marker.test.js` with the exact content below. The sandbox mirrors the pattern in `tc.test.js` but also stubs `localStorage` (state.js calls `loadState`/`loadMoods`/`loadDefaults`/`loadPools` at load time, all of which read localStorage).

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadStateSandbox() {
  const sandbox = {
    window: { CC: {} },
    console,
    FPS: 25,
    localStorage: {
      _data: {},
      getItem(k) { return this._data[k] || null; },
      setItem(k, v) { this._data[k] = String(v); },
    },
  };
  vm.createContext(sandbox);
  for (const f of ['constants.js', 'util.js', 'state.js']) {
    const code = fs.readFileSync(path.resolve(__dirname, '..', 'js', f), 'utf8');
    vm.runInContext(code, sandbox, { filename: f });
  }
  return sandbox.window.CC.state;
}

function makeSong(cuesArr) {
  return { id: 'song1', name: '', sequence: 1, audioFileName: '', cues: cuesArr };
}
function cue(n, position) {
  // Tests only care about n and position; other fields stay empty to mirror
  // marker-dropped cues. Test helpers stay narrow on purpose.
  return { n, position, name: '', actions: [], fade: '', delay: '', collapsed: false };
}

test('appendCueWithTcAndResort: inserts in TC order and renumbers n = 1..N', () => {
  const S = loadStateSandbox();
  const song = makeSong([cue(1, '00:00:10:00'), cue(2, '00:00:30:00')]);
  S.appendCueWithTcAndResort(song, '00:00:20:00');
  assert.strictEqual(song.cues.length, 3);
  assert.deepStrictEqual(song.cues.map(c => c.position),
    ['00:00:10:00', '00:00:20:00', '00:00:30:00']);
  assert.deepStrictEqual(song.cues.map(c => c.n), [1, 2, 3]);
});

test('appendCueWithTcAndResort: empty cue list → single cue with n = 1', () => {
  const S = loadStateSandbox();
  const song = makeSong([]);
  S.appendCueWithTcAndResort(song, '00:00:05:00');
  assert.strictEqual(song.cues.length, 1);
  assert.strictEqual(song.cues[0].n, 1);
  assert.strictEqual(song.cues[0].position, '00:00:05:00');
});

test('appendCueWithTcAndResort: new cue has expected empty shape', () => {
  const S = loadStateSandbox();
  const song = makeSong([]);
  S.appendCueWithTcAndResort(song, '00:00:05:00');
  const c = song.cues[0];
  assert.strictEqual(c.name, '');
  assert.strictEqual(c.fade, '');
  assert.strictEqual(c.delay, '');
  assert.strictEqual(c.collapsed, false);
  assert.ok(Array.isArray(c.actions) && c.actions.length === 1, 'one empty action');
});

test('appendCueWithTcAndResort: null/undefined song → no throw, no mutation', () => {
  const S = loadStateSandbox();
  S.appendCueWithTcAndResort(null, '00:00:05:00');
  S.appendCueWithTcAndResort(undefined, '00:00:05:00');
  // No assertion needed beyond "did not throw"
});

test('resortAndRenumber: idempotent (running twice produces same result)', () => {
  const S = loadStateSandbox();
  const song = makeSong([cue(3, '00:00:30:00'), cue(1, '00:00:10:00'), cue(2, '00:00:20:00')]);
  S.resortAndRenumber(song);
  const first = song.cues.map(c => ({ n: c.n, position: c.position }));
  S.resortAndRenumber(song);
  const second = song.cues.map(c => ({ n: c.n, position: c.position }));
  assert.deepStrictEqual(first, second);
  assert.deepStrictEqual(first.map(c => c.n), [1, 2, 3]);
  assert.deepStrictEqual(first.map(c => c.position),
    ['00:00:10:00', '00:00:20:00', '00:00:30:00']);
});

test('resortAndRenumber: cues with empty/invalid TC sort to the end', () => {
  const S = loadStateSandbox();
  const song = makeSong([
    cue(1, ''),                 // invalid
    cue(2, '00:00:20:00'),      // valid
    cue(3, 'garbage'),          // invalid
    cue(4, '00:00:05:00'),      // valid
  ]);
  S.resortAndRenumber(song);
  // Valid TCs first in ascending order, then the two invalid ones.
  assert.deepStrictEqual(song.cues.map(c => c.position),
    ['00:00:05:00', '00:00:20:00', '', 'garbage']);
  assert.deepStrictEqual(song.cues.map(c => c.n), [1, 2, 3, 4]);
});

test('resortAndRenumber: null/undefined song → no throw', () => {
  const S = loadStateSandbox();
  S.resortAndRenumber(null);
  S.resortAndRenumber(undefined);
  S.resortAndRenumber({ cues: null });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

```
cd web && npm test -- --test-name-pattern="appendCueWithTcAndResort|resortAndRenumber"
```

Expected: FAIL with messages like `TypeError: S.appendCueWithTcAndResort is not a function`.

- [ ] **Step 3: Implement the helpers in `web/js/state.js`**

Add the two functions immediately after `function newCue()` (around line 37 — anywhere in the function-definition block is fine; pick this spot to keep cue-related helpers together).

```js
function appendCueWithTcAndResort(song, tc) {
  if (!song || !Array.isArray(song.cues)) return;
  song.cues.push({
    n: 0,
    position: tc,
    name: '',
    actions: [newAction()],
    fade: '',
    delay: '',
    collapsed: false
  });
  resortAndRenumber(song);
}

function resortAndRenumber(song) {
  if (!song || !Array.isArray(song.cues)) return;
  song.cues.sort((a, b) => {
    const sa = timecodeToSeconds(a.position);
    const sb = timecodeToSeconds(b.position);
    if (isNaN(sa) && isNaN(sb)) return 0;
    if (isNaN(sa)) return 1;   // invalid TCs sink to the end
    if (isNaN(sb)) return -1;
    return sa - sb;
  });
  song.cues.forEach((c, i) => { c.n = i + 1; });
}
```

- [ ] **Step 4: Extend the `CC.state` export at the bottom of `state.js`**

Find the line starting `CC.state = { newSong, newProject, ...`. Add the two new function names anywhere in the list. After the change it should look like:

```js
CC.state = { newSong, newProject, activeSong, newCue, newAction, appendCueWithTcAndResort, resortAndRenumber, migrateActions, migrateCues, migrateState, loadState, saveState, loadMoods, saveMoods, newMood, makeDefaults, loadDefaults, saveDefaults, emptyPools, loadPools, savePools, cloneActions, actionIsEmpty, parsePoolsPaste, saveProject, loadProject, parseCsv, importCsv };
```

- [ ] **Step 5: Run the tests to verify they pass**

```
cd web && npm test
```

Expected: all marker tests pass; existing `tc.test.js` and `transport.test.js` still pass.

- [ ] **Step 6: Commit**

```
cd web && cd ..
git add web/js/state.js web/test/marker.test.js
git commit -m "feat(web): state helpers for marker-driven cue authoring

appendCueWithTcAndResort and resortAndRenumber. Pure helpers that
take a song object directly so they're trivially testable. Used by
the M-hotkey drop flow and the drag/delete paths in audio.js.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: audio.js — drop, select, drag, delete (no unit tests; DOM-bound)

**Files:**
- Modify: `web/js/audio.js`

These changes touch live DOM and the WebAudio element. Test manually in Task 5.

- [ ] **Step 1: Add module-local selection state**

Near the top of `audio.js`, alongside the other `let` declarations (around line 6-13), add:

```js
let selectedMarkerCueN = null;
let markerDragState = null; // { cueN, startX, durationS, timelineRect } during a drag, else null
```

- [ ] **Step 2: Add `dropMarkerAtPlayhead`**

Add this function after `captureCurrentPlayheadAsSmpte` (around line 349-352). It is the M-hotkey entry point.

```js
function dropMarkerAtPlayhead() {
  const song = activeSong();
  if (!song || !audioEl || !audioBuffer) return;
  const tc = captureCurrentPlayheadAsSmpte();
  if (!tc) return;
  CC.state.appendCueWithTcAndResort(song, tc);
  saveState();
  render();
}
```

- [ ] **Step 3: Add selection helpers**

Add after `dropMarkerAtPlayhead`:

```js
function selectMarker(cueN) {
  selectedMarkerCueN = cueN;
  document.querySelectorAll('#markers .marker').forEach(m => {
    m.classList.toggle('selected', m.dataset.cueN === String(cueN));
  });
}

function deselectAllMarkers() {
  selectedMarkerCueN = null;
  document.querySelectorAll('#markers .marker.selected').forEach(m => m.classList.remove('selected'));
}

function getSelectedMarkerCueN() {
  return selectedMarkerCueN;
}
```

- [ ] **Step 4: Add `deleteSelectedMarker`**

```js
function deleteSelectedMarker() {
  if (selectedMarkerCueN == null) return false;
  const song = activeSong();
  if (!song) return false;
  const idx = song.cues.findIndex(c => c.n === selectedMarkerCueN);
  if (idx < 0) { selectedMarkerCueN = null; return false; }
  song.cues.splice(idx, 1);
  CC.state.resortAndRenumber(song);
  selectedMarkerCueN = null;
  saveState();
  render();
  return true;
}
```

(Returns `true` so the keydown handler can `preventDefault` and avoid browser back-navigation on Backspace.)

- [ ] **Step 5: Add `startMarkerDrag` and its window listeners**

```js
function startMarkerDrag(cueN, evt) {
  if (!audioBuffer) return;
  const tl = document.getElementById('timeline');
  if (!tl) return;
  evt.preventDefault();
  selectMarker(cueN);
  markerDragState = {
    cueN,
    timelineRect: tl.getBoundingClientRect(),
    durationS: audioBuffer.duration
  };
  document.body.style.cursor = 'grabbing';
  window.addEventListener('mousemove', onMarkerDragMove);
  window.addEventListener('mouseup', onMarkerDragEnd);
}

function onMarkerDragMove(evt) {
  if (!markerDragState) return;
  const song = activeSong();
  if (!song) return;
  const { cueN, timelineRect, durationS } = markerDragState;
  const cue = song.cues.find(c => c.n === cueN);
  if (!cue) return;
  let pct = (evt.clientX - timelineRect.left) / timelineRect.width;
  pct = Math.max(0, Math.min(1, pct));
  const seconds = pct * durationS;
  cue.position = secondsToTimecode(seconds);
  // Cheap live update: move just the pin, skip full render() for perf.
  const pin = document.querySelector(`#markers .marker[data-cue-n="${cueN}"]`);
  if (pin) pin.style.left = (pct * 100) + '%';
}

function onMarkerDragEnd() {
  if (!markerDragState) return;
  const song = activeSong();
  markerDragState = null;
  document.body.style.cursor = '';
  window.removeEventListener('mousemove', onMarkerDragMove);
  window.removeEventListener('mouseup', onMarkerDragEnd);
  if (song) {
    CC.state.resortAndRenumber(song);
    saveState();
    render();
  }
}
```

Note on the data attribute: in the existing `renderMarkers` (line 330) the dataset key is `cueN`, which renders as `data-cue-n` in HTML (camelCase → kebab-case). The `querySelector` above must use the kebab-case form.

- [ ] **Step 6: Update `renderMarkers` to attach click + mousedown handlers**

Find the `renderMarkers` function (around line 315). Inside the `song.cues.forEach(cue => { ... })` block, replace the existing `m.addEventListener('click', ...)` block with the version below. Keep everything before and after unchanged.

Original block (around lines 336-343):
```js
    m.addEventListener('click', e => {
      e.stopPropagation();
      audioEl.currentTime = s;
      song.cues.forEach(c => c.collapsed = (c.n !== cue.n));
      saveState();
      render();
    });
    markers.appendChild(m);
```

Replace with:
```js
    if (selectedMarkerCueN === cue.n) m.classList.add('selected');
    m.addEventListener('mousedown', e => {
      // Start drag immediately; selection happens as a side effect.
      e.stopPropagation();
      startMarkerDrag(cue.n, e);
    });
    m.addEventListener('click', e => {
      e.stopPropagation();
      // If the mousedown started a drag, mouseup landed elsewhere already
      // cleared markerDragState; a plain click (no drag) selects + scrubs.
      selectMarker(cue.n);
      audioEl.currentTime = s;
      song.cues.forEach(c => c.collapsed = (c.n !== cue.n));
      saveState();
      render();
    });
    markers.appendChild(m);
```

- [ ] **Step 7: Update the timeline click handler to deselect markers**

Find the existing timeline-click listener in `renderAudioPanel` (around line 220-227):

```js
  const tl = document.getElementById('timeline');
  tl.addEventListener('click', e => {
    if (e.target.classList.contains('marker')) return;
    const rect = tl.getBoundingClientRect();
    const pct = (e.clientX - rect.left) / rect.width;
    audioEl.currentTime = Math.max(0, Math.min(dur, pct * dur));
    updatePlayhead();
  });
```

Replace with:

```js
  const tl = document.getElementById('timeline');
  tl.addEventListener('click', e => {
    if (e.target.classList.contains('marker') || e.target.classList.contains('marker-label')) return;
    deselectAllMarkers();
    const rect = tl.getBoundingClientRect();
    const pct = (e.clientX - rect.left) / rect.width;
    audioEl.currentTime = Math.max(0, Math.min(dur, pct * dur));
    updatePlayhead();
  });
```

(Also covers `.marker-label` because clicks on the label text were already being treated as marker clicks via event bubbling — being explicit prevents an accidental deselect when clicking the label.)

- [ ] **Step 8: Extend the `CC.audio` export**

Find the last line of `audio.js` (around line 356):

```js
window.CC.audio = { loadAudioFile, setActiveAudioFromCache, setChannelMute, drawWaveform, renderAudioPanel, wireLoadAudio, togglePlay, startPlayheadLoop, stopPlayheadLoop, updatePlayhead, updateCurrentMarker, renderMarkers, captureCurrentPlayheadAsSmpte };
```

Replace with:

```js
window.CC.audio = { loadAudioFile, setActiveAudioFromCache, setChannelMute, drawWaveform, renderAudioPanel, wireLoadAudio, togglePlay, startPlayheadLoop, stopPlayheadLoop, updatePlayhead, updateCurrentMarker, renderMarkers, captureCurrentPlayheadAsSmpte, dropMarkerAtPlayhead, selectMarker, deselectAllMarkers, deleteSelectedMarker, getSelectedMarkerCueN };
```

- [ ] **Step 9: Run existing tests to confirm no regression**

```
cd web && npm test
```

Expected: all tests pass (audio.js has no node tests; only checking we didn't break `state.js` or `util.js`).

- [ ] **Step 10: Commit**

```
git add web/js/audio.js
git commit -m "feat(web): marker drop / drag / select / delete in audio module

dropMarkerAtPlayhead is the M-hotkey entry point. selectMarker +
deselectAllMarkers manage the highlight state. startMarkerDrag uses
window-level mousemove/mouseup to nudge a pin; live updates the pin
position and the cue's TC field, then resort+renumber on mouseup.
deleteSelectedMarker removes the selected cue and resort+renumbers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: CSS for selected marker + grab cursors

**Files:**
- Modify: `web/css/styles.css`

- [ ] **Step 1: Find the existing marker block**

It starts around line 677 (`#timeline .marker { ... }`). After the `:hover` rule (~line 686) and before `.marker.current` (~line 687), add the new rules.

- [ ] **Step 2: Add `.marker.selected` highlight + grab cursors**

Insert these rules:

```css
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
```

(Note: `#timeline .marker` already has a base ruleset around line 677; the `cursor: grab` line here adds a property. If the engineer prefers, merge it into the existing block — either is fine, just don't define `.marker` twice with conflicting `background`/`width` values.)

- [ ] **Step 3: Visual sanity check**

Open `web/index.html` in a browser or the desktop app. Load a track that already has cues with TCs → markers render. Confirm hovering shows the grab cursor and the existing yellow hover effect still works (i.e., the new rule didn't conflict).

- [ ] **Step 4: Commit**

```
git add web/css/styles.css
git commit -m "style(web): selected-marker highlight + grab cursor

.marker.selected uses a brighter version of the existing hover yellow
to make the selection state obvious. grab/grabbing handled via the base
.marker cursor + JS body cursor during drag.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Global keydown handler in main.js

**Files:**
- Modify: `web/js/main.js`

- [ ] **Step 1: Add the new keydown handler**

Find the existing keydown listener at line 124-136 (`document.addEventListener('keydown', e => { ... if (e.code === 'Space' && audioEl) { ... } });`). **Add a separate listener** immediately after it. Two listeners avoid mixing the existing modal-Escape and Space-play logic with the new keys.

Insert after line 136 (i.e. right after the closing `});` of the existing handler):

```js
// Marker hotkeys: M to drop at playhead, Delete/Backspace to remove the
// selected marker. Both no-op while typing in form fields.
document.addEventListener('keydown', e => {
  const tag = (e.target.tagName || '').toUpperCase();
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || e.target.isContentEditable) return;
  if (e.key === 'm' || e.key === 'M') {
    e.preventDefault();
    CC.audio.dropMarkerAtPlayhead();
    return;
  }
  if (e.key === 'Delete' || e.key === 'Backspace') {
    if (CC.audio.deleteSelectedMarker()) {
      e.preventDefault();
    }
  }
});
```

- [ ] **Step 2: Run existing tests to confirm no regression**

```
cd web && npm test
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```
git add web/js/main.js
git commit -m "feat(web): global M / Delete hotkeys for marker authoring

Separate keydown listener — kept apart from the existing modal-Escape
and Space-play handler so the responsibilities stay readable. Bails on
INPUT/TEXTAREA/SELECT/contenteditable so cue-name typing isn't hijacked.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Manual E2E test

**Files:** none changed unless a defect surfaces.

Goal: walk the 6 manual test cases from the spec and confirm the feature works end-to-end in the actual app.

- [ ] **Step 1: Launch the desktop app**

```
cd desktop && npm start
```

Wait for the Electron window to open.

- [ ] **Step 2: Load a track and add markers in order**

1. Click "Load Audio…", pick any audio file.
2. Press Play.
3. Press `M` four times at intervals during playback.

Expected: 4 cues appear in the cue list with `n` 1..4, ascending TC values. 4 pins on the waveform.

- [ ] **Step 3: Drop a marker out of order (resort + renumber)**

1. Pause.
2. Scrub back (click on the waveform timeline) to a point before the first marker.
3. Press `M`.

Expected: the new marker becomes Cue 1; the previous Cue 1..4 renumber to 2..5. Both the cue list and the pin positions reflect the new order.

- [ ] **Step 4: Drag a marker to nudge timing**

1. Mousedown on one of the pins on the waveform.
2. Drag left/right.

Expected during drag: the pin moves with the cursor; the cue's `position` field shown elsewhere updates only at mouseup (cheap-render path). On mouseup, the cue list re-sorts if the drag crossed another marker, and all cues renumber.

- [ ] **Step 5: Select + delete a marker**

1. Click a pin (no drag).

Expected: pin gets the yellow highlight (`.selected`).

2. Press `Delete` (or `Backspace`).

Expected: pin disappears, its cue is removed from the list, remaining cues renumber.

- [ ] **Step 6: Focus-safe M**

1. Click into a cue's "Name" text field.
2. Type the letter `m`.

Expected: the letter `m` appears in the name field. No marker drops, no cue created.

- [ ] **Step 7: No-audio guard**

1. Use "Add Song" to create a new song with no audio loaded.
2. Press `M`.

Expected: no-op, no error in the dev console.

- [ ] **Step 8: If anything failed, fix and commit**

Diagnose with the dev console (`Ctrl+Shift+I` in the Electron app). Likely failure modes:
- M does nothing → check the keydown listener is wired (Task 4) and `CC.audio.dropMarkerAtPlayhead` is exported (Task 2 Step 8).
- Marker doesn't highlight on click → check Task 2 Step 6 replaced the click handler correctly.
- Drag does nothing → check `data-cue-n` selector matches the dataset key (`cueN` → `data-cue-n` is correct in HTML).
- Delete navigates back instead of deleting → check `deleteSelectedMarker` returns `true` and the keydown handler calls `e.preventDefault()` (Task 4 Step 1).

Fix any defect, commit a small follow-up with prefix `fix(web):`, re-test from the failing step onward.

- [ ] **Step 9: If everything passed, no commit needed**

The feature is complete on the existing commits from Tasks 1-4.

---

## Self-review

**Spec coverage:**
- "Load track, press M, cue appears" → Task 2 Step 2 + Task 4. Manual Step 2 verifies.
- "Drop in playback or paused" → Task 2 Step 2 (no `audioEl.paused` check). Manual Step 3 covers paused case.
- "Drag pin nudges TC live" → Task 2 Step 5 (`onMarkerDragMove` updates `cue.position` + pin DOM each tick). Manual Step 4.
- "Click + Delete removes" → Task 2 Step 4 + Task 4. Manual Step 5.
- "Resort + renumber after every mutation" → Tasks 1, 2 Step 4, 2 Step 5 (`onMarkerDragEnd`).
- "M no-op while typing" → Task 4 Step 1 input/textarea/select/contenteditable guard. Manual Step 6.
- "M no-op without audio" → Task 2 Step 2 `!audioEl || !audioBuffer` guard. Manual Step 7.
- "Drag clamp to `[0, duration]`" → Task 2 Step 5 (`Math.max(0, Math.min(1, pct))`).
- "Selected marker visible" → Task 3 CSS.

**Placeholder scan:** No TBDs, no "implement later", every step has runnable code or a runnable command.

**Type/signature consistency:** `appendCueWithTcAndResort(song, tc)` and `resortAndRenumber(song)` signatures match between Task 1 (definitions + tests) and Task 2 (call sites). `data-cue-n` attribute name is consistent: it's set automatically by JS via `m.dataset.cueN` in the existing `renderMarkers` (audio.js line 330) and queried via `[data-cue-n="..."]` in Task 2 Step 5 — that's the correct HTML form.
