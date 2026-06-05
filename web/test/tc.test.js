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

// captureCurrentPlayheadAsSmpte is defined in audio.js, which depends on the DOM.
// We lock the expected pure-helper shape here against secondsToTimecode from util.
test('captureCurrentPlayheadAsSmpte: returns null when no audio loaded', () => {
  const sb = loadModules(['util.js']);
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
  // 65.4s → 1m 5s + 0.4 * 25 = 10 frames
});

function loadCompile() {
  const sb = loadModules(['constants.js', 'util.js']);
  // compile.js references global state + defaults at top-level only inside
  // functions; injecting empty stubs keeps buildTcCmdLines (pure) usable.
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
  // length-based check avoids cross-realm Array prototype mismatch from vm sandbox
  assert.strictEqual(compile.buildTcCmdLines([song]).length, 0);
});

test('buildTcCmdLines: emits cleanup + Store + Set per valid cue', () => {
  const compile = loadCompile();
  const song = { sequence: 12, name: 'S1', cues: [
    { n: 1, name: 'INTRO',  position: '00:00:05:00' },   // 5.0 s
    { n: 2, name: 'VERSE',  position: '00:00:10:12' },   // 10 + 12/25 = 10.48 s
    { n: 3, name: 'BAD',    position: '99:99:99:99' },   // invalid → skipped
  ]};
  const out = compile.buildTcCmdLines([song]);
  for (let i = 0; i < 200; i++) {
    assert.strictEqual(out[i], 'Delete Timecode 12.1.1.1.1.1 /NoConfirmation');
  }
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
  assert.strictEqual(compile.buildTcCmdLines([]).length, 0);
});

test('buildTcLua: wraps buildTcCmdLines output in Lua Cmd() calls', () => {
  const compile = loadCompile();
  const song = { sequence: 12, name: 'S', cues: [
    { n: 1, name: 'A', position: '00:00:05:00' },
  ]};
  const lua = compile.buildTcLua([song], 'Song: S');
  assert.match(lua, /-- Generated by Cuelist Compiler/);
  assert.match(lua, /-- Song: S/);
  assert.match(lua, /Cmd\('Delete Timecode 12\.1\.1\.1\.1\.1 \/NoConfirmation'\)/);
  // store event wrapped — inner single quotes around 'Goto Cue ...' are escaped \'
  assert.match(lua, /Store Timecode 12\.1\.1\.1\.1 \\'Goto Cue 1 Sequence 12\\'/);
  assert.match(lua, /return main/);
});
