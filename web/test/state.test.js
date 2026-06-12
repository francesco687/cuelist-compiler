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
  // state.js uses both `window.CC` and bare `CC` — wire them together.
  const CC = {};
  const window = { CC };
  const sandbox = {
    window,
    CC,
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
  return sandbox.CC.state;
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
  try {
    const cue = st.newCue();
    assert.strictEqual(cue.includeStore, true);
    assert.strictEqual(cue.includeTc, true);
  } finally {
    delete global.state;
  }
});
