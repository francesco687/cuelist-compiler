'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadAudioHelpers() {
  const sandbox = { window: { CC: {} }, console, FPS: 25 };
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

test('pickTickInterval: sub-second buckets when zoomed in tight', () => {
  const { pickTickInterval } = loadAudioHelpers();
  assert.deepEqual(pickTickInterval(2),   { interval: 0.1,  major: 0.5 });
  assert.deepEqual(pickTickInterval(5),   { interval: 0.25, major: 1   });
  assert.deepEqual(pickTickInterval(10),  { interval: 0.5,  major: 2   });
});

test('pickTickInterval: 10–30s window keeps 1s ticks for SMPTE familiarity', () => {
  const { pickTickInterval } = loadAudioHelpers();
  assert.deepEqual(pickTickInterval(15),  { interval: 1, major: 5 });
  assert.deepEqual(pickTickInterval(30),  { interval: 1, major: 5 });
});

test('pickTickInterval: minute-scale buckets between 30s and 10min', () => {
  const { pickTickInterval } = loadAudioHelpers();
  assert.deepEqual(pickTickInterval(31),  { interval: 2,  major: 10  });
  assert.deepEqual(pickTickInterval(120), { interval: 5,  major: 30  });
  assert.deepEqual(pickTickInterval(300), { interval: 10, major: 60  });
  assert.deepEqual(pickTickInterval(600), { interval: 30, major: 120 });
});

test('pickTickInterval: hour-scale buckets beyond 10min', () => {
  const { pickTickInterval } = loadAudioHelpers();
  assert.deepEqual(pickTickInterval(1800), { interval: 60,  major: 300  });
  assert.deepEqual(pickTickInterval(3600), { interval: 120, major: 600  });
  assert.deepEqual(pickTickInterval(7200), { interval: 300, major: 1800 });
});

test('formatRulerLabel: sub-second precision when zoomed under 2s', () => {
  const { formatRulerLabel } = loadAudioHelpers();
  assert.strictEqual(formatRulerLabel(1.5, 2),  '1.5s');
  assert.strictEqual(formatRulerLabel(0.3, 1),  '0.3s');
});

test('formatRulerLabel: MM:SS for the common minute scale', () => {
  const { formatRulerLabel } = loadAudioHelpers();
  assert.strictEqual(formatRulerLabel(65, 120),  '01:05');
  assert.strictEqual(formatRulerLabel(0,  120),  '00:00');
});

test('formatRulerLabel: promotes to HH:MM:SS when total > 1h or t >= 1h', () => {
  const { formatRulerLabel } = loadAudioHelpers();
  assert.strictEqual(formatRulerLabel(65,    7200), '00:01:05');
  assert.strictEqual(formatRulerLabel(3661,  300),  '01:01:01');
});

test('formatRulerLabel: explicit HH format trims to hours only', () => {
  const { formatRulerLabel } = loadAudioHelpers();
  assert.strictEqual(formatRulerLabel(7265, 60, 'hh'), '02');  // 2h 1m 5s -> 02
  assert.strictEqual(formatRulerLabel(0,    60, 'hh'), '00');
});

test('formatRulerLabel: explicit HH:MM format', () => {
  const { formatRulerLabel } = loadAudioHelpers();
  assert.strictEqual(formatRulerLabel(7265, 60, 'hh-mm'), '02:01');
  assert.strictEqual(formatRulerLabel(125,  60, 'hh-mm'), '00:02');
});

test('formatRulerLabel: explicit HH:MM:SS format ignores zoom and shows full triplet', () => {
  const { formatRulerLabel } = loadAudioHelpers();
  assert.strictEqual(formatRulerLabel(65,    60, 'hh-mm-ss'), '00:01:05');
  assert.strictEqual(formatRulerLabel(3725,  60, 'hh-mm-ss'), '01:02:05');
});

test('formatRulerLabel: explicit HH:MM:SS:FF format adds frames at 25fps', () => {
  const { formatRulerLabel } = loadAudioHelpers();
  // 5.4 s @ 25 fps -> 0.4 s = 10 frames
  assert.strictEqual(formatRulerLabel(5.4, 60, 'hh-mm-ss-ff'), '00:00:05:10');
  // 65 s exactly -> 00 frames
  assert.strictEqual(formatRulerLabel(65,  60, 'hh-mm-ss-ff'), '00:01:05:00');
});

test('formatRulerLabel: unknown format falls back to auto', () => {
  const { formatRulerLabel } = loadAudioHelpers();
  assert.strictEqual(formatRulerLabel(65, 120, 'bogus'), '01:05');
});

test('clampSeek: inside window passes through', () => {
  const { clampSeek } = loadAudioHelpers();
  // Lower bound is headS (head trim), not startS (audio-mobile shift).
  assert.strictEqual(clampSeek(5, { startS: 0, endS: 9, headS: 1 }, 10), 5);
});

test('clampSeek: before headS clamps to headS', () => {
  const { clampSeek } = loadAudioHelpers();
  assert.strictEqual(clampSeek(0.5, { startS: 0, endS: 9, headS: 1 }, 10), 1);
});

test('clampSeek: after endS clamps to endS', () => {
  const { clampSeek } = loadAudioHelpers();
  assert.strictEqual(clampSeek(9.5, { startS: 0, endS: 9, headS: 1 }, 10), 9);
});

test('clampSeek: endS=null clamps to duration on the right', () => {
  const { clampSeek } = loadAudioHelpers();
  assert.strictEqual(clampSeek(15, { startS: 0, endS: null, headS: 0 }, 10), 10);
});

test('clampSeek: missing headS defaults to 0 (backward-compat)', () => {
  const { clampSeek } = loadAudioHelpers();
  assert.strictEqual(clampSeek(0.5, { startS: 1, endS: 9 }, 10), 0.5);
});

test('clampSeek: startS does NOT act as a lower bound (it is the song-time shift)', () => {
  const { clampSeek } = loadAudioHelpers();
  // startS being positive used to incorrectly clamp seek to startS. Now only headS does.
  assert.strictEqual(clampSeek(0.5, { startS: 5, endS: 9, headS: 0 }, 10), 0.5);
});

test('shouldAutoPause: past endS while playing -> true', () => {
  const { shouldAutoPause } = loadAudioHelpers();
  assert.strictEqual(shouldAutoPause(9.1, { startS: 0, endS: 9 }, false), true);
});

test('shouldAutoPause: at endS exactly -> true', () => {
  const { shouldAutoPause } = loadAudioHelpers();
  assert.strictEqual(shouldAutoPause(9, { startS: 0, endS: 9 }, false), true);
});

test('shouldAutoPause: inside window -> false', () => {
  const { shouldAutoPause } = loadAudioHelpers();
  assert.strictEqual(shouldAutoPause(5, { startS: 0, endS: 9 }, false), false);
});

test('shouldAutoPause: endS=null -> false', () => {
  const { shouldAutoPause } = loadAudioHelpers();
  assert.strictEqual(shouldAutoPause(99999, { startS: 0, endS: null }, false), false);
});

test('shouldAutoPause: already paused -> false (idempotent)', () => {
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

test('findPrevMarker: returns largest cue strictly before now - 0.25s tolerance', () => {
  const { findPrevMarker } = loadAudioHelpers();
  const cues = [
    { n: 1, position: '00:00:01:00' },
    { n: 2, position: '00:00:05:00' },
    { n: 3, position: '00:00:10:00' }
  ];
  assert.strictEqual(findPrevMarker(7.0, cues), cues[1]);
  assert.strictEqual(findPrevMarker(5.0, cues), cues[0]);
  assert.strictEqual(findPrevMarker(0.5, cues), null);
});

test('findNextMarker: returns smallest cue strictly after now + 0.05s tolerance', () => {
  const { findNextMarker } = loadAudioHelpers();
  const cues = [
    { n: 1, position: '00:00:01:00' },
    { n: 2, position: '00:00:05:00' },
    { n: 3, position: '00:00:10:00' }
  ];
  assert.strictEqual(findNextMarker(3.0, cues), cues[1]);
  assert.strictEqual(findNextMarker(5.0, cues), cues[2]);
  assert.strictEqual(findNextMarker(10.0, cues), null);
  assert.strictEqual(findNextMarker(99.0, cues), null);
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
