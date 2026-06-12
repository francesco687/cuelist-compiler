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
  assert.ok(joined.includes('Store Sequence 1 Cue 1 "A"'), 'cue 1 must emit');
  assert.ok(joined.includes('Store Sequence 1 Cue 3 "C"'), 'cue 3 must emit');
  assert.ok(!joined.includes('Cue 2 "B"'), 'cue 2 must not emit');
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
  assert.ok(lua.includes('{name="S", seq=1, cues={'));
  assert.ok(!lua.includes('{n=1, name="A"'));
});
