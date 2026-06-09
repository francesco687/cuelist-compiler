'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

// Unambiguous code — generated once on the laptop, typed into the phone by hand.
// Lowercase + digits only, with the look-alikes 0/1/i/l/o removed (31-char alphabet,
// ~44 bits over 9 chars). No capitals/underscore so there's no case or symbol to
// fat-finger — a base64url code like `d4jQVvOab_ZY` was too error-prone to type.
const CODE_ALPHABET = '23456789abcdefghjkmnpqrstuvwxyz';
const CODE_LEN = 9;
function generatePairingCode() {
  const bytes = crypto.randomBytes(CODE_LEN);
  let out = '';
  for (let i = 0; i < CODE_LEN; i++) out += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  return out;
}

function defaults() {
  return {
    relayUrl: 'wss://cuelist-relay.fly.dev',
    pairingCode: generatePairingCode(),
    ma3Host: '127.0.0.1',
    ma3Port: 8000,
    ma3Prefix: 'gma3',
    intervalMs: 20,
    pullFile: '/Users/Shared/cuelist-pull/sequences.json',
    pullTrigger: 'Call Plugin 21',
    pullTimeoutMs: 8000,
  };
}

function merge(base, partial) { return Object.assign({}, base, partial || {}); }

function validate(s) {
  const port = (name, v) => {
    if (!Number.isInteger(v) || v < 1 || v > 65535) throw new Error(`invalid ${name}: ${v}`);
  };
  port('ma3Port', s.ma3Port);
  if (typeof s.relayUrl !== 'string' || !/^wss?:\/\//.test(s.relayUrl)) throw new Error('invalid relayUrl');
  if (typeof s.pairingCode !== 'string' || !/^[a-z0-9]{6,}$/.test(s.pairingCode)) throw new Error('invalid pairingCode');
  if (typeof s.ma3Host !== 'string' || !s.ma3Host) throw new Error('invalid ma3Host');
  if (typeof s.ma3Prefix !== 'string' || !s.ma3Prefix) throw new Error('invalid ma3Prefix');
  if (!Number.isInteger(s.intervalMs) || s.intervalMs < 0) throw new Error('invalid intervalMs');
  return s;
}

function filePath(userDataDir) { return path.join(userDataDir, 'settings.json'); }

function load(userDataDir) {
  let raw;
  try {
    raw = fs.readFileSync(filePath(userDataDir), 'utf8');
  } catch (e) {
    if (e.code === 'ENOENT') return defaults();   // genuinely no file yet → first-run defaults
    throw e;                                        // file exists but unreadable → surface, never mint a new code
  }
  // Parse/validate errors propagate on purpose: a corrupt EXISTING settings file
  // must NOT silently fall back to a fresh-code defaults() — that would change the
  // pairing code and drop every paired phone. Atomic save (below) prevents the
  // truncated-write corruption that used to trigger this.
  return validate(merge(defaults(), JSON.parse(raw)));
}

function save(userDataDir, s) {
  const v = validate(merge(defaults(), s));
  // Atomic write: serialize to a temp file then rename over the target, so an
  // interrupted write (crash/quit mid-save) can never leave settings.json
  // half-written — the old reparse-corruption-into-a-new-pairing-code vector.
  const target = filePath(userDataDir);
  const tmp = target + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(v, null, 2));
  fs.renameSync(tmp, target);
  return v;
}

function loadOrInit(userDataDir) {
  if (!fs.existsSync(filePath(userDataDir))) return save(userDataDir, defaults());
  return load(userDataDir);
}

module.exports = { defaults, merge, validate, load, save, loadOrInit, filePath, generatePairingCode };
