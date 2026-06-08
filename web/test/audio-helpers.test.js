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

test('pickTickInterval: <=30s -> 1s ticks, major every 5s', () => {
  const { pickTickInterval } = loadAudioHelpers();
  assert.deepEqual(pickTickInterval(15),  { interval: 1, major: 5 });
  assert.deepEqual(pickTickInterval(30),  { interval: 1, major: 5 });
});

test('pickTickInterval: <=2min -> 5s ticks, major every 30s', () => {
  const { pickTickInterval } = loadAudioHelpers();
  assert.deepEqual(pickTickInterval(31),  { interval: 5, major: 30 });
  assert.deepEqual(pickTickInterval(120), { interval: 5, major: 30 });
});

test('pickTickInterval: >2min -> 10s ticks, major every 60s', () => {
  const { pickTickInterval } = loadAudioHelpers();
  assert.deepEqual(pickTickInterval(121), { interval: 10, major: 60 });
  assert.deepEqual(pickTickInterval(600), { interval: 10, major: 60 });
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
