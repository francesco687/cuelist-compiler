'use strict';
// Loads the real web/js compiler into a Node VM and exposes migrate + buildCmdLines.
// This is why the hub needs no Swift/Node re-implementation: it runs compile.js itself.
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const POOLS = ['color', 'dimmer', 'position', 'gobo', 'beam', 'focus'];

/** Builds a fresh VM context with the web modules loaded; returns the exposed API. */
function createCompiler({ webJsDir } = {}) {
  const dir = webJsDir || path.resolve(__dirname, '..', '..', 'web', 'js');
  const read = (f) => fs.readFileSync(path.join(dir, f), 'utf8');

  const sandbox = {
    console,
    localStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} },
    document: {
      createElement: () => ({ click() {}, style: {}, setAttribute() {} }),
      body: { appendChild() {}, removeChild() {} },
      getElementById: () => null,
    },
    alert: () => {},
    Blob: function () {},
    URL: { createObjectURL: () => '', revokeObjectURL: () => {} },
    setTimeout: () => {},
    Date, Math, JSON, parseInt, parseFloat, isNaN, isFinite, String, Number, Object, Array,
  };
  // Browser parity: in a browser window === globalThis, so the web modules'
  // `window.CC = window.CC || {}` namespace registers a real global `CC`.
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);

  const combined = [
    read('constants.js'),
    read('util.js'),
    read('state.js'),
    read('compile.js'),
    'globalThis.__api = { buildCmdLines, migrateState, makeDefaults,' +
    '  setState: (s) => { state = s; }, setDefaults: (d) => { defaults = d; } };',
  ].join('\n;\n');

  vm.runInContext(combined, sandbox, { filename: 'compile-bundle.js' });
  return sandbox.__api;
}

function normalizeDefaults(d) {
  const out = {};
  for (const p of POOLS) {
    const v = (d && d[p]) || {};
    out[p] = { fade: v.fade != null ? v.fade : '', delay: v.delay != null ? v.delay : '' };
  }
  return out;
}

/** Migrates + compiles a show to OSC command lines. Throws if the selection has no cues. */
function compileShow(api, { project, defaults, selection }) {
  const migrated = api.migrateState(project);
  if (!migrated || !Array.isArray(migrated.songs)) throw new Error('invalid project');
  api.setState(migrated);
  api.setDefaults(defaults ? normalizeDefaults(defaults) : api.makeDefaults());

  let songs;
  if (selection === 'current') {
    const active = migrated.songs.find((s) => s.id === migrated.activeSongId) || migrated.songs[0];
    songs = active && Array.isArray(active.cues) && active.cues.length ? [active] : [];
  } else {
    songs = migrated.songs.filter((s) => Array.isArray(s.cues) && s.cues.length);
  }
  if (songs.length === 0) throw new Error('no cues to send');
  // Marshal out of the VM context: buildCmdLines returns a VM-realm Array whose
  // prototype differs from the host Array, causing deepStrictEqual failures.
  return Array.from(api.buildCmdLines(songs)).map(String);
}

module.exports = { createCompiler, compileShow, normalizeDefaults };
