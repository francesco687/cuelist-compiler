'use strict';
const fs = require('node:fs');
const path = require('node:path');

function defaults() {
  return {
    ma3Host: '127.0.0.1',
    ma3Port: 8000,
    ma3Prefix: 'gma3',
    intervalMs: 20,
    hubEnabled: true,
    hubPort: 9000,
  };
}

function merge(base, partial) {
  return Object.assign({}, base, partial || {});
}

function validate(s) {
  const port = (name, v) => {
    if (!Number.isInteger(v) || v < 1 || v > 65535) throw new Error(`invalid ${name}: ${v}`);
  };
  port('ma3Port', s.ma3Port);
  port('hubPort', s.hubPort);
  if (!s.ma3Host) throw new Error('invalid ma3Host');
  if (!s.ma3Prefix) throw new Error('invalid ma3Prefix');
  if (!Number.isInteger(s.intervalMs) || s.intervalMs < 0) throw new Error('invalid intervalMs');
  return s;
}

// Electron-only persistence helpers (not exercised by unit tests).
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

module.exports = { defaults, merge, validate, load, save, filePath };
