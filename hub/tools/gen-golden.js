'use strict';
// Regenerates examples/SONG_1.cmdlines.txt from the web JS reference.
// Run: node hub/tools/gen-golden.js   (from repo root)
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const repo = path.resolve(__dirname, '..', '..'); // hub/tools -> repo root
const webjs = (p) => fs.readFileSync(path.join(repo, 'web', 'js', p), 'utf8');

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
  webjs('constants.js'),
  webjs('util.js'),
  webjs('state.js'),
  webjs('compile.js'),
  'globalThis.__api = { buildCmdLines, migrateState, makeDefaults,' +
  '  setState: (s) => { state = s; }, setDefaults: (d) => { defaults = d; } };',
].join('\n;\n');

vm.runInContext(combined, sandbox, { filename: 'compile-bundle.js' });
const api = sandbox.__api;

const raw = JSON.parse(fs.readFileSync(path.join(repo, 'examples', 'SONG_1.json'), 'utf8'));
const migrated = api.migrateState(raw);
api.setState(migrated);
api.setDefaults(api.makeDefaults());

const lines = api.buildCmdLines(migrated.songs);
const out = path.join(repo, 'examples', 'SONG_1.cmdlines.txt');
fs.writeFileSync(out, lines.join('\n') + '\n');
console.log('wrote ' + path.relative(repo, out) + ' (' + lines.length + ' lines)');
