'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { createCompiler, compileShow } = require('../src/compile-bridge');

const repo = path.resolve(__dirname, '..', '..');
const golden = fs.readFileSync(path.join(repo, 'examples', 'SONG_1.cmdlines.txt'), 'utf8')
  .split('\n').filter((l) => l.length > 0);
const song1 = JSON.parse(fs.readFileSync(path.join(repo, 'examples', 'SONG_1.json'), 'utf8'));

test('compileShow(all) matches the golden lines', () => {
  const api = createCompiler();
  const lines = compileShow(api, { project: song1, selection: 'all' });
  assert.deepStrictEqual(lines, golden);
});

test('compileShow(current) on a single-song show matches the golden lines', () => {
  const api = createCompiler();
  const lines = compileShow(api, { project: song1, selection: 'current' });
  assert.deepStrictEqual(lines, golden);
});

test('compileShow throws when nothing has cues', () => {
  const api = createCompiler();
  const empty = { songs: [{ id: 's1', name: '', sequence: 1, cues: [] }], activeSongId: 's1', storeMode: 'Overwrite' };
  assert.throws(() => compileShow(api, { project: empty, selection: 'all' }), /no cues/);
});

test('defaults supply fade fallback', () => {
  const api = createCompiler();
  const project = {
    songs: [{ id: 's1', name: 'S', sequence: 1, cues: [
      { n: 1, name: 'Q', fade: '', delay: '', actions: [
        { group: 'G', presets: { color: { name: 'C', fade: '', delay: '' } } }
      ] }
    ] }],
    activeSongId: 's1', storeMode: 'Overwrite'
  };
  const defaults = { color: { fade: '3', delay: '' } };
  const lines = compileShow(api, { project, defaults, selection: 'all' });
  assert.ok(lines.includes('Fade 3 FeatureGroup 4'), lines.join('\n'));
});
