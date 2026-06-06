'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const { defaults, merge, validate, generatePairingCode } = require('../src/settings');

test('defaults include relay + ma3 fields and a generated pairing code', () => {
  const d = defaults();
  assert.strictEqual(d.relayUrl, 'wss://cuelist-relay.fly.dev');
  assert.strictEqual(d.ma3Host, '127.0.0.1');
  assert.strictEqual(d.ma3Port, 8000);
  assert.strictEqual(d.ma3Prefix, 'gma3');
  assert.ok(d.pairingCode.length >= 8, 'pairing code should be >= 8 chars');
});

test('generatePairingCode uses an unambiguous lowercase alphabet, >= 8 chars', () => {
  const code = generatePairingCode();
  // lowercase + digits only, no look-alikes (0/1/i/l/o) and no case-sensitivity — easy to hand-type
  assert.ok(/^[23456789abcdefghjkmnpqrstuvwxyz]{8,}$/.test(code), `unexpected code: ${code}`);
  assert.ok(!/[01ilo]/.test(code), `code has ambiguous chars: ${code}`);
  assert.notStrictEqual(generatePairingCode(), generatePairingCode());
});

test('validate rejects a bad ma3 port', () => {
  assert.throws(() => validate(merge(defaults(), { ma3Port: 0 })), /invalid ma3Port/);
});

test('validate rejects an empty relay url', () => {
  assert.throws(() => validate(merge(defaults(), { relayUrl: '' })), /invalid relayUrl/);
});

test('validate rejects a short pairing code', () => {
  assert.throws(() => validate(merge(defaults(), { pairingCode: 'abc' })), /invalid pairingCode/);
});
