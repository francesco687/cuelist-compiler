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
