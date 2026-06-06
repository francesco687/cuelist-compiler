'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadStateSandbox() {
  const win = { CC: {} };
  const sandbox = {
    window: win,
    console,
    FPS: 25,
    localStorage: {
      _data: {},
      getItem(k) { return this._data[k] || null; },
      setItem(k, v) { this._data[k] = String(v); },
    },
  };
  // state.js writes `window.CC = window.CC || {}` then uses bare `CC.state = …`
  // In a real browser window.CC creates a global CC; in vm we wire it up manually.
  Object.defineProperty(sandbox, 'CC', {
    get() { return sandbox.window.CC; },
    set(v) { sandbox.window.CC = v; },
    configurable: true,
  });
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
    cue(1, ''),
    cue(2, '00:00:20:00'),
    cue(3, 'garbage'),
    cue(4, '00:00:05:00'),
  ]);
  S.resortAndRenumber(song);
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
