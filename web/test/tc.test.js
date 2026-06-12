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

test('buildTcCmdLines: emits one Lua command per song using Object API', () => {
  const compile = loadCompile();
  const song = { sequence: 12, name: 'S1', cues: [
    { n: 1, name: 'INTRO',  position: '00:00:05:00' },   // 5.0 s → 83886080 rawtime
    { n: 2, name: 'VERSE',  position: '00:00:10:12' },   // 10.48 s → 175825224 rawtime
    { n: 3, name: 'BAD',    position: '99:99:99:99' },   // invalid → skipped
  ]};
  const out = compile.buildTcCmdLines([song]);
  assert.strictEqual(out.length, 1);
  const line = out[0];
  // Outer wrapper: command-line Lua keyword + double-quoted code
  assert.ok(line.startsWith('Lua "') && line.endsWith('"'), 'expected Lua "..." wrapper');
  // Resolves the sequence + timecode pool by sequence number
  assert.ok(line.includes('DataPool().sequences[12]'));
  assert.ok(line.includes('DataPool().timecodes[12]'));
  // Selective overwrite: targets tg[2] and deletes only events whose
  // cuedestination.no matches a cue in the send list.
  assert.ok(line.includes('local tr=tg[2]'), 'must target tg[2] not tg:Children()[1]');
  assert.ok(line.includes('sb:Delete(i)'), 'must clear events via parent CmdSubTrack:Delete(index)');
  assert.ok(!line.includes('tr:Delete('), 'must not delete TimeRanges (prohibited on real desk)');
  assert.ok(!line.includes('trc[i]:Delete()'), 'no-arg child :Delete() is the broken form (Wrong parameter #2)');
  assert.ok(line.includes(":Acquire('CmdSubTrack')"));
  // Cues sorted ascending with valid one only, rawtime = round(seconds * 16777216)
  assert.ok(line.includes('{{1,83886080},{2,175825224}}'));
  // Sets event properties via Object API, not Property keyword
  assert.ok(line.includes("e:Set('rawtime',c[2])"));
  assert.ok(line.includes("e:Set('cuedestination',cue)"));
  // Cue lookup by displayed number against the target sequence
  assert.ok(line.includes("GetObject('Sequence 12 Cue '..c[1])"));
  // Selective overwrite: must build a sendNos set and check destination cue number
  assert.ok(line.includes('sendNos'), 'must use sendNos set for selective overwrite');
  assert.ok(line.includes('sendNos[math.floor(c[1]*1000+0.5)]=true'),
    'must build sendNos keyed by MA3 internal ×1000 cue-no scaling');
  assert.ok(line.includes('sendNos[d.no]'), 'must check destination.no against send set');
});

test('buildTcCmdLines: handles multiple songs, sorted cues by n ascending', () => {
  const compile = loadCompile();
  const songs = [
    { sequence: 1, name: 'A', cues: [
      { n: 2, name: '', position: '00:00:02:00' },     // 2s → 33554432
      { n: 1, name: '', position: '00:00:01:00' },     // 1s → 16777216
    ]},
    { sequence: 2, name: 'B', cues: [
      { n: 1, name: '', position: '00:00:00:12' },     // 0.48s → 8053064
    ]},
  ];
  const out = compile.buildTcCmdLines(songs);
  assert.strictEqual(out.length, 2);
  // Song A: cues re-sorted ascending by n
  assert.ok(out[0].includes('DataPool().sequences[1]'));
  assert.ok(out[0].includes('{{1,16777216},{2,33554432}}'));
  // Song B: single cue
  assert.ok(out[1].includes('DataPool().sequences[2]'));
  assert.ok(out[1].includes('{{1,8053064}}'));
});

test('buildTcCmdLines: decimal cue numbers emit as Lua-parseable floats', () => {
  const compile = loadCompile();
  const song = { sequence: 666, cues: [
    { n: 0.1, name: 'DB',    position: '00:00:05:15' }, // 5.6s → 93952410
    { n: 1,   name: 'INTRO', position: '00:00:10:00' }, // 10s  → 167772160
  ]};
  const out = compile.buildTcCmdLines([song]);
  assert.strictEqual(out.length, 1);
  // 0.1 < 1 so sorting keeps DB first
  assert.ok(out[0].includes('{{0.1,93952410},{1,167772160}}'));
});

test('buildTcCmdLines: returns [] for empty input', () => {
  const compile = loadCompile();
  assert.strictEqual(compile.buildTcCmdLines([]).length, 0);
});

test('buildTcLua: emits a standalone Object-API plugin', () => {
  const compile = loadCompile();
  const song = { sequence: 12, name: 'S', cues: [
    { n: 1, name: 'A', position: '00:00:05:00' },  // 5s → 83886080
  ]};
  const lua = compile.buildTcLua([song], 'Song: S');
  assert.match(lua, /-- Generated by Cuelist Compiler — TIMECODE EVENTS \(Object API\)/);
  assert.match(lua, /-- Song: S/);
  // BEHAVIOR comment must describe selective semantic, not wipe-all
  assert.match(lua, /-- BEHAVIOR: selectively overwrites events for the cues in `cues`/);
  // Standalone applySong helper using Acquire / cuedestination
  assert.match(lua, /local function applySong\(seq, cues\)/);
  assert.match(lua, /local tr = tg\[2\]/); // user Track sits at TG index 2, not 1
  assert.match(lua, /sb:Delete\(i\)/); // clears events (not TimeRanges), parent:Delete(index)
  assert.ok(!/trc\[i\]:Delete\(\)/.test(lua), 'no-arg child :Delete() is the broken form');
  // Selective overwrite: reuse existing CmdSubTrack; only Acquire fresh if track is empty
  assert.match(lua, /local sub = nil/);
  assert.match(lua, /if not sub then/);
  assert.match(lua, /e:Set\("rawtime", c\[2\]\)/);
  assert.match(lua, /e:Set\("cuedestination", cue\)/);
  // Selective overwrite: sendNos set (×1000 scaled) and destination.no check
  assert.match(lua, /sendNos\[math\.floor\(c\[1\]\*1000\+0\.5\)\] = true/);
  assert.match(lua, /sendNos\[d\.no\]/);
  // SONGS table holds the data; main loops it
  assert.match(lua, /\{ seq=12, cues=\{\{1,83886080\}\} \},/);
  assert.match(lua, /for _, song in ipairs\(SONGS\) do applySong\(song\.seq, song\.cues\) end/);
  assert.match(lua, /return main/);
});

test('regression: SONG_1.json matches SONG_1.tc.cmdlines.txt golden', () => {
  const compile = loadCompile();
  const json = JSON.parse(fs.readFileSync(path.resolve(__dirname, '..', '..', 'examples', 'SONG_1.json'), 'utf8'));
  const songs = Array.isArray(json.songs) ? json.songs
    : [{ name: json.songName || '', sequence: json.sequence, cues: json.cues }];
  const expected = fs.readFileSync(path.resolve(__dirname, '..', '..', 'examples', 'SONG_1.tc.cmdlines.txt'), 'utf8').trimEnd();
  const actual = compile.buildTcCmdLines(songs).join('\n');
  assert.strictEqual(actual, expected);
});

test('buildTcCmdLines: skips cues with includeTc=false', () => {
  const compile = loadCompile();
  const song = { sequence: 1, name: 'S', cues: [
    { n: 1, name: 'A', position: '00:00:01:00', includeTc: true },
    { n: 2, name: 'B', position: '00:00:02:00', includeTc: false },
    { n: 3, name: 'C', position: '00:00:03:00', includeTc: true },
  ]};
  const out = compile.buildTcCmdLines([song]);
  assert.strictEqual(out.length, 1);
  assert.ok(out[0].includes('{{1,16777216},{3,50331648}}'),
    'expected only cues 1 and 3 in the events table');
  assert.ok(!out[0].includes('33554432'),
    'cue 2 rawtime must not be present');
});

test('buildTcLua: skips cues with includeTc=false from SONGS table', () => {
  const compile = loadCompile();
  const song = { sequence: 1, name: 'S', cues: [
    { n: 1, name: 'A', position: '00:00:01:00', includeTc: false },
    { n: 2, name: 'B', position: '00:00:02:00', includeTc: true },
  ]};
  const lua = compile.buildTcLua([song], 'Song: S');
  assert.ok(lua.includes('cues={{2,33554432}}'),
    'expected only cue 2 in SONGS cues');
  assert.ok(!lua.includes('{1,16777216}'),
    'cue 1 rawtime must not appear');
});

test('buildTcCmdLines: includeStore=false does NOT filter TC path', () => {
  const compile = loadCompile();
  const song = { sequence: 1, name: 'S', cues: [
    { n: 1, name: 'A', position: '00:00:01:00', includeStore: false, includeTc: true },
  ]};
  const out = compile.buildTcCmdLines([song]);
  assert.strictEqual(out.length, 1);
  assert.ok(out[0].includes('{{1,16777216}}'));
});
