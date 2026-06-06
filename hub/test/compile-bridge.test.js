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

test('selection: current returns only the active song; all returns both', () => {
  const api = createCompiler();
  const mk = (id, seq, group, presetName, cueName) => ({
    id, name: id, sequence: seq,
    cues: [{ n: 1, name: cueName, fade: '', delay: '', actions: [
      { group, presets: { color: { name: presetName, fade: '', delay: '' } } }
    ] }],
  });
  const project = {
    songs: [ mk('s1', 1, 'G1', 'C1', 'CUE_ONE'), mk('s2', 2, 'G2', 'C2', 'CUE_TWO') ],
    activeSongId: 's2', storeMode: 'Overwrite',
  };

  const all = compileShow(api, { project, selection: 'all' });
  const current = compileShow(api, { project, selection: 'current' });

  // 'all' includes both songs' groups/cues; 'current' includes only the active (s2) song's.
  assert.ok(all.includes('Group "G1"') && all.includes('Group "G2"'), all.join('\n'));
  assert.ok(current.includes('Group "G2"'), current.join('\n'));
  assert.ok(!current.includes('Group "G1"'), 'current must exclude the non-active song: ' + current.join('\n'));
});

test('cue note emits a Set "Note" line after Store on the OSC path', () => {
  const api = createCompiler();
  const project = {
    songs: [{ id: 's1', name: 'S', sequence: 7, cues: [
      { n: 1, name: 'Q1', fade: '', delay: '',
        notes: 'tighten on the "hot" spot\nsecond line',
        actions: [{ group: 'G', presets: { color: { name: 'C', fade: '', delay: '' } } }] },
      { n: 2, name: 'Q2', fade: '', delay: '', notes: '   ',
        actions: [{ group: 'G', presets: { color: { name: 'C', fade: '', delay: '' } } }] },
    ] }],
    activeSongId: 's1', storeMode: 'Overwrite',
  };
  const lines = compileShow(api, { project, selection: 'all' });

  const noteLine = 'Set Sequence 7 Cue 1 "Note" "tighten on the \\"hot\\" spot second line"';
  const storeIdx = lines.indexOf('Store Sequence 7 Cue 1 "Q1" /Overwrite /NoConfirmation');
  const noteIdx = lines.indexOf(noteLine);
  assert.ok(storeIdx !== -1, 'store line present');
  assert.ok(noteIdx === storeIdx + 1, 'note line immediately after its Store');
  // whitespace-only note emits nothing
  assert.ok(!lines.some((l) => l.startsWith('Set Sequence 7 Cue 2 "Note"')), 'empty note emits no line');
});

test('cue note appears in the exported Lua plugin (data + emitter)', () => {
  const api = createCompiler();
  const project = {
    songs: [{ id: 's1', name: 'S', sequence: 7, cues: [
      { n: 1, name: 'Q1', fade: '', delay: '', notes: 'tighten on the "hot" spot',
        actions: [{ group: 'G', presets: { color: { name: 'C', fade: '', delay: '' } } }] },
    ] }],
    activeSongId: 's1', storeMode: 'Overwrite',
  };
  const migrated = api.migrateState(project);
  const lua = String(api.buildLua(migrated.songs, 'T'));

  // data table carries the sanitized + escaped note
  assert.ok(lua.includes('note="tighten on the \\"hot\\" spot"'), 'note in SONGS table');
  // main loop emits the Set "Note" command when c.note is present
  assert.ok(
    lua.includes('Cmd(\'Set Sequence \'..song.seq..\' Cue \'..c.n..\' "Note" "\'..c.note..\'"\')'),
    'note emitter in main loop'
  );
});
