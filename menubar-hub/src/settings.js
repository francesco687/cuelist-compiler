'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

// 12-char url-safe code (~71 bits) — generated once on the laptop, typed into the phone.
function generatePairingCode() {
  return crypto.randomBytes(9).toString('base64url').slice(0, 12);
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
  if (typeof s.pairingCode !== 'string' || s.pairingCode.length < 8) throw new Error('invalid pairingCode');
  if (typeof s.ma3Host !== 'string' || !s.ma3Host) throw new Error('invalid ma3Host');
  if (typeof s.ma3Prefix !== 'string' || !s.ma3Prefix) throw new Error('invalid ma3Prefix');
  if (!Number.isInteger(s.intervalMs) || s.intervalMs < 0) throw new Error('invalid intervalMs');
  return s;
}

function filePath(userDataDir) { return path.join(userDataDir, 'settings.json'); }

function load(userDataDir) {
  try {
    const raw = fs.readFileSync(filePath(userDataDir), 'utf8');
    return validate(merge(defaults(), JSON.parse(raw)));
  } catch { return defaults(); }
}

function save(userDataDir, s) {
  const v = validate(merge(defaults(), s));
  fs.writeFileSync(filePath(userDataDir), JSON.stringify(v, null, 2));
  return v;
}

module.exports = { defaults, merge, validate, load, save, filePath, generatePairingCode };
