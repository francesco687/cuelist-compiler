'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const { loadConfig } = require('../src/config');

test('defaults when env empty', () => {
  const c = loadConfig({});
  assert.strictEqual(c.host, '0.0.0.0');
  assert.strictEqual(c.port, 9000);
  assert.strictEqual(c.ma3Host, '127.0.0.1');
  assert.strictEqual(c.ma3Port, 8000);
  assert.strictEqual(c.ma3Prefix, 'gma3');
  assert.strictEqual(c.intervalMs, 20);
});

test('env overrides parse to numbers', () => {
  const c = loadConfig({ HUB_PORT: '9100', MA3_HOST: '10.0.0.5', MA3_PORT: '8001', MA3_PREFIX: 'ma', OSC_INTERVAL_MS: '5' });
  assert.strictEqual(c.port, 9100);
  assert.strictEqual(c.ma3Host, '10.0.0.5');
  assert.strictEqual(c.ma3Port, 8001);
  assert.strictEqual(c.ma3Prefix, 'ma');
  assert.strictEqual(c.intervalMs, 5);
});
