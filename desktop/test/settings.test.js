'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const { defaults, merge, validate } = require('../settings');

test('defaults match hub expectations', () => {
  const d = defaults();
  assert.strictEqual(d.ma3Host, '127.0.0.1');
  assert.strictEqual(d.ma3Port, 8000);
  assert.strictEqual(d.ma3Prefix, 'gma3');
  assert.strictEqual(d.hubEnabled, true);
  assert.strictEqual(d.hubPort, 9000);
  assert.strictEqual(d.intervalMs, 20);
});

test('merge overlays partial user settings onto defaults', () => {
  const m = merge(defaults(), { ma3Host: '10.0.0.2', hubPort: 9100 });
  assert.strictEqual(m.ma3Host, '10.0.0.2');
  assert.strictEqual(m.hubPort, 9100);
  assert.strictEqual(m.ma3Port, 8000); // untouched
});

test('validate rejects out-of-range ports', () => {
  assert.throws(() => validate(merge(defaults(), { ma3Port: 70000 })), /ma3Port/);
  assert.throws(() => validate(merge(defaults(), { hubPort: 0 })), /hubPort/);
});

test('validate accepts a sane config', () => {
  assert.doesNotThrow(() => validate(defaults()));
});
