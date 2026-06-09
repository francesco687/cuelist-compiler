'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { defaults, merge, validate, generatePairingCode, load, save, loadOrInit, filePath } = require('../src/settings');

test('defaults include relay + ma3 fields and the fixed brand pairing code', () => {
  const d = defaults();
  assert.strictEqual(d.relayUrl, 'wss://cuelist-relay.fly.dev');
  assert.strictEqual(d.ma3Host, '127.0.0.1');
  assert.strictEqual(d.ma3Port, 8000);
  assert.strictEqual(d.ma3Prefix, 'gma3');
  assert.strictEqual(d.pairingCode, 'blearred');   // memorable, stable across fresh installs
  assert.doesNotThrow(() => validate(d), 'the default code must satisfy validate()');
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

test('validate accepts a memorable custom code of 6+ lowercase-alnum', () => {
  assert.doesNotThrow(() => validate(merge(defaults(), { pairingCode: 'tour2026' })));
});

test('validate rejects codes shorter than 6 or with bad chars', () => {
  assert.throws(() => validate(merge(defaults(), { pairingCode: 'ab2' })), /invalid pairingCode/);
  assert.throws(() => validate(merge(defaults(), { pairingCode: 'TOUR2026' })), /invalid pairingCode/);
});

test('loadOrInit writes defaults on first run and is stable across reloads', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'saetta-set-'));
  try {
    assert.strictEqual(fs.existsSync(filePath(dir)), false);
    const first = loadOrInit(dir);
    assert.strictEqual(fs.existsSync(filePath(dir)), true);
    const second = loadOrInit(dir);
    assert.strictEqual(second.pairingCode, first.pairingCode);   // not regenerated
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('a settings save that does not touch the code preserves the pairing code', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'saetta-set-'));
  try {
    const first = loadOrInit(dir);
    const code = first.pairingCode;
    save(dir, merge(first, { ma3Host: '10.0.0.101' }));   // e.g. user sets the desk IP
    assert.strictEqual(load(dir).pairingCode, code);       // code survives unrelated saves
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('load throws on a corrupt EXISTING file instead of silently minting a new code', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'saetta-set-'));
  try {
    fs.writeFileSync(filePath(dir), '{ truncated jso');   // simulate an interrupted write
    // Must NOT return a fresh-code defaults() — that would drop every paired phone.
    assert.throws(() => load(dir));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('save is atomic — leaves no .tmp behind and the file is complete', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'saetta-set-'));
  try {
    save(dir, defaults());
    assert.strictEqual(fs.existsSync(filePath(dir) + '.tmp'), false, 'no leftover temp file');
    const parsed = JSON.parse(fs.readFileSync(filePath(dir), 'utf8'));
    assert.ok(parsed.pairingCode.length >= 8);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
