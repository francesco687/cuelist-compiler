# Cuelist Compiler — M1 Plan A: Raspberry Pi Hub

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Node service (runs on the Pi) that receives a show from the iPhone over WebSocket, compiles it by running the *real* `web/js/compile.js`, and relays the resulting OSC command lines to grandMA3 over UDP.

**Architecture:** `hub/` is a small Node project. `compile-bridge.js` loads the existing web modules into a Node VM (browser shims) and exposes `migrateState` + `buildCmdLines` — so the MA3 contract is reused verbatim, with **zero changes to `web/`**. `osc.js` ports the OSC encoder + UDP socket from `proxy/ws2osc.js`. `server.js` speaks the phone↔hub protocol. The existing golden fixture `examples/SONG_1.cmdlines.txt` guards correctness end-to-end.

**Tech Stack:** Node 26 (built-in `node:test`, `dgram`, global `WebSocket` client), `ws` (server), `vm`.

**Design doc:** `docs/superpowers/specs/2026-06-04-ios-frontend-design.md`

**Protocol (phone → hub):**
```
→ { type: "compile-send", project: {songs, activeSongId, storeMode}, defaults, selection: "current"|"all" }
← { type: "progress", sent, total }   ← { type: "done", total }   ← { type: "error", message }
(legacy: → { type: "cmd", line }  ← { type: "sent", line };  → { type: "ping" } ← { type: "pong" })
```

**Standard test command (from repo root):**
```bash
cd hub && npm test
```

---

## Task 1: hub/ scaffold + green test loop

**Files:**
- Create: `hub/package.json`
- Create: `hub/src/config.js`
- Create: `hub/test/config.test.js`
- Create: `hub/.gitignore`

- [ ] **Step 1: Write `hub/package.json`**

```json
{
  "name": "cuelist-hub",
  "version": "0.1.0",
  "private": true,
  "description": "Raspberry Pi hub: compiles shows via web/js/compile.js and relays OSC to grandMA3.",
  "type": "commonjs",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js",
    "test": "node --test"
  },
  "dependencies": {
    "ws": "^8.18.0"
  },
  "engines": {
    "node": ">=20"
  }
}
```

- [ ] **Step 2: Write `hub/.gitignore`**

```
node_modules/
*.log
```

- [ ] **Step 3: Write the failing test `hub/test/config.test.js`**

```javascript
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
```

- [ ] **Step 4: Run, verify it fails**

Run: `cd hub && npm install && npm test`
Expected: `config` module not found / FAIL.

- [ ] **Step 5: Write `hub/src/config.js`**

```javascript
'use strict';

/** Reads hub configuration from an env-like object. */
function loadConfig(env = process.env) {
  const int = (v, d) => {
    const n = parseInt(v, 10);
    return Number.isFinite(n) ? n : d;
  };
  return {
    host: env.HUB_HOST || '0.0.0.0',
    port: int(env.HUB_PORT, 9000),
    ma3Host: env.MA3_HOST || '127.0.0.1',
    ma3Port: int(env.MA3_PORT, 8000),
    ma3Prefix: env.MA3_PREFIX || 'gma3',
    intervalMs: int(env.OSC_INTERVAL_MS, 20),
    webJsDir: env.WEB_JS_DIR || undefined, // defaults to ../web/js inside compile-bridge
  };
}

module.exports = { loadConfig };
```

- [ ] **Step 6: Run, verify it passes.** Expected: both `config` tests PASS.

- [ ] **Step 7: Commit**

```bash
git add hub/package.json hub/package-lock.json hub/.gitignore hub/src/config.js hub/test/config.test.js
git commit -m "feat(hub): scaffold Node project + config"
```

---

## Task 2: OSC encoding + UDP sender (port of ws2osc.js)

**Files:**
- Create: `hub/src/osc.js`
- Create: `hub/test/osc.test.js`

- [ ] **Step 1: Write the failing test `hub/test/osc.test.js`**

```javascript
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const dgram = require('node:dgram');
const { oscString, buildOscMessage, OscSender } = require('../src/osc');

test('oscString pads to 4-byte boundary with null terminator', () => {
  assert.deepStrictEqual([...oscString('abc')], [97, 98, 99, 0]);          // 3+null = 4
  assert.deepStrictEqual([...oscString('abcd')], [97, 98, 99, 100, 0, 0, 0, 0]); // 4+null -> pad 8
});

test('buildOscMessage layout for ClearAll', () => {
  const msg = buildOscMessage('/gma3/cmd', ['ClearAll']);
  // addr 12 + typetag 4 + arg 12
  assert.strictEqual(msg.length, 28);
  assert.strictEqual(msg.length % 4, 0);
  assert.deepStrictEqual([...msg.subarray(0, 12)], [...Buffer.from('/gma3/cmd'), 0, 0, 0]);
  assert.deepStrictEqual([...msg.subarray(12, 16)], [...Buffer.from(',s'), 0, 0]);
});

test('OscSender delivers a datagram to a UDP listener', async () => {
  const rx = dgram.createSocket('udp4');
  const got = [];
  rx.on('message', (m) => got.push(Buffer.from(m)));
  await new Promise((r) => rx.bind(0, '127.0.0.1', r));
  const port = rx.address().port;

  const sender = new OscSender({ host: '127.0.0.1', port, prefix: 'gma3' });
  await sender.send('Group "X"');
  await new Promise((r) => setTimeout(r, 100));
  sender.close();
  rx.close();

  assert.strictEqual(got.length, 1);
  assert.deepStrictEqual([...got[0].subarray(0, 12)], [...Buffer.from('/gma3/cmd'), 0, 0, 0]);
});
```

- [ ] **Step 2: Run, verify it fails** (`osc` module missing).

- [ ] **Step 3: Write `hub/src/osc.js`**

```javascript
'use strict';
// OSC 1.0 encoding + UDP sender. Port of proxy/ws2osc.js.
const dgram = require('node:dgram');

function oscString(s) {
  const body = Buffer.from(s + '\0', 'binary');
  const padLen = (4 - (body.length % 4)) % 4;
  return padLen ? Buffer.concat([body, Buffer.alloc(padLen)]) : body;
}

function oscInt(n) {
  const b = Buffer.alloc(4);
  b.writeInt32BE(n | 0, 0);
  return b;
}

function oscFloat(n) {
  const b = Buffer.alloc(4);
  b.writeFloatBE(n, 0);
  return b;
}

function buildOscMessage(address, args) {
  let types = ',';
  const parts = [];
  for (const a of args) {
    if (typeof a === 'string') { types += 's'; parts.push(oscString(a)); }
    else if (typeof a === 'number' && Number.isInteger(a)) { types += 'i'; parts.push(oscInt(a)); }
    else if (typeof a === 'number') { types += 'f'; parts.push(oscFloat(a)); }
    else { throw new Error('unsupported OSC arg type: ' + typeof a); }
  }
  return Buffer.concat([oscString(address), oscString(types), ...parts]);
}

/** Holds one UDP socket and sends OSC `/prefix/cmd` messages to a target. */
class OscSender {
  constructor({ host, port, prefix }) {
    this.host = host;
    this.port = port;
    this.address = '/' + prefix + '/cmd';
    this.udp = dgram.createSocket('udp4');
  }

  send(line) {
    return new Promise((resolve, reject) => {
      let pkt;
      try { pkt = buildOscMessage(this.address, [line]); }
      catch (e) { reject(e); return; }
      this.udp.send(pkt, this.port, this.host, (err) => (err ? reject(err) : resolve()));
    });
  }

  close() { try { this.udp.close(); } catch { /* already closed */ } }
}

module.exports = { oscString, oscInt, oscFloat, buildOscMessage, OscSender };
```

- [ ] **Step 4: Run, verify it passes.** Expected: all 3 `osc` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add hub/src/osc.js hub/test/osc.test.js
git commit -m "feat(hub): OSC encoder + UDP sender (port of ws2osc.js)"
```

---

## Task 3: Golden fixture generator + `examples/SONG_1.cmdlines.txt`

Generates the regression golden by running the web reference in a Node VM. This is the file the bridge + server tests assert against. (Carried over from the superseded engine plan; now lives in `hub/tools/`.)

**Files:**
- Create: `hub/tools/gen-golden.js`
- Create (generated): `examples/SONG_1.cmdlines.txt`

- [ ] **Step 1: Write `hub/tools/gen-golden.js`**

```javascript
'use strict';
// Regenerates examples/SONG_1.cmdlines.txt from the web JS reference.
// Run: node hub/tools/gen-golden.js   (from repo root)
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const repo = path.resolve(__dirname, '..', '..'); // hub/tools -> repo root
const webjs = (p) => fs.readFileSync(path.join(repo, 'web', 'js', p), 'utf8');

const sandbox = {
  console,
  localStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} },
  document: {
    createElement: () => ({ click() {}, style: {}, setAttribute() {} }),
    body: { appendChild() {}, removeChild() {} },
    getElementById: () => null,
  },
  alert: () => {},
  Blob: function () {},
  URL: { createObjectURL: () => '', revokeObjectURL: () => {} },
  setTimeout: () => {},
  Date, Math, JSON, parseInt, parseFloat, isNaN, isFinite, String, Number, Object, Array,
};
// Browser parity: in a browser window === globalThis, so the web modules'
// `window.CC = window.CC || {}` namespace registers a real global `CC`.
sandbox.window = sandbox;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);

const combined = [
  webjs('constants.js'),
  webjs('util.js'),
  webjs('state.js'),
  webjs('compile.js'),
  'globalThis.__api = { buildCmdLines, migrateState, makeDefaults,' +
  '  setState: (s) => { state = s; }, setDefaults: (d) => { defaults = d; } };',
].join('\n;\n');

vm.runInContext(combined, sandbox, { filename: 'compile-bundle.js' });
const api = sandbox.__api;

const raw = JSON.parse(fs.readFileSync(path.join(repo, 'examples', 'SONG_1.json'), 'utf8'));
const migrated = api.migrateState(raw);
api.setState(migrated);
api.setDefaults(api.makeDefaults());

const lines = api.buildCmdLines(migrated.songs);
const out = path.join(repo, 'examples', 'SONG_1.cmdlines.txt');
fs.writeFileSync(out, lines.join('\n') + '\n');
console.log('wrote ' + path.relative(repo, out) + ' (' + lines.length + ' lines)');
```

- [ ] **Step 2: Run the generator** (from repo root)

Run: `node hub/tools/gen-golden.js`
Expected: `wrote examples/SONG_1.cmdlines.txt (18 lines)`

- [ ] **Step 3: Verify content**

Run: `cat examples/SONG_1.cmdlines.txt`
Expected exactly:
```
ClearAll
Group "AROLLA FLOOR"
At Preset 4."BLUE"
At Preset 1."DIMMER 100"
At Preset 2."LOW"
At Preset 6."MEDIUM"
Store Sequence 666 Cue 0.1 "DB CUE" /Overwrite /NoConfirmation
Set Sequence 666 Cue 0.1 Fade 5
ClearAll
Group "AROLLA FLOOR"
At Preset 4."RED"
At Preset 1."DIMMER 0"
At Preset 2."AUD"
At Preset 6."WIDE"
Store Sequence 666 Cue 1 "INTRO" /Overwrite /NoConfirmation
Set Sequence 666 Cue 1 Fade 6
ClearAll
```
If it differs, STOP and reconcile before continuing.

- [ ] **Step 4: Commit**

```bash
git add hub/tools/gen-golden.js examples/SONG_1.cmdlines.txt
git commit -m "feat(hub): golden cmd-lines fixture generated from JS reference"
```

---

## Task 4: compile-bridge — run web/js/compile.js in a Node VM

**Files:**
- Create: `hub/src/compile-bridge.js`
- Create: `hub/test/compile-bridge.test.js`

- [ ] **Step 1: Write the failing test `hub/test/compile-bridge.test.js`**

```javascript
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
```

- [ ] **Step 2: Run, verify it fails** (`compile-bridge` missing).

- [ ] **Step 3: Write `hub/src/compile-bridge.js`**

```javascript
'use strict';
// Loads the real web/js compiler into a Node VM and exposes migrate + buildCmdLines.
// This is why the hub needs no Swift/Node re-implementation: it runs compile.js itself.
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const POOLS = ['color', 'dimmer', 'position', 'gobo', 'beam', 'focus'];

/** Builds a fresh VM context with the web modules loaded; returns the exposed API. */
function createCompiler({ webJsDir } = {}) {
  const dir = webJsDir || path.resolve(__dirname, '..', '..', 'web', 'js');
  const read = (f) => fs.readFileSync(path.join(dir, f), 'utf8');

  const sandbox = {
    console,
    localStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} },
    document: {
      createElement: () => ({ click() {}, style: {}, setAttribute() {} }),
      body: { appendChild() {}, removeChild() {} },
      getElementById: () => null,
    },
    alert: () => {},
    Blob: function () {},
    URL: { createObjectURL: () => '', revokeObjectURL: () => {} },
    setTimeout: () => {},
    Date, Math, JSON, parseInt, parseFloat, isNaN, isFinite, String, Number, Object, Array,
  };
  // Browser parity: in a browser window === globalThis, so the web modules'
  // `window.CC = window.CC || {}` namespace registers a real global `CC`.
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);

  const combined = [
    read('constants.js'),
    read('util.js'),
    read('state.js'),
    read('compile.js'),
    'globalThis.__api = { buildCmdLines, migrateState, makeDefaults,' +
    '  setState: (s) => { state = s; }, setDefaults: (d) => { defaults = d; } };',
  ].join('\n;\n');

  vm.runInContext(combined, sandbox, { filename: 'compile-bundle.js' });
  return sandbox.__api;
}

function normalizeDefaults(d) {
  const out = {};
  for (const p of POOLS) {
    const v = (d && d[p]) || {};
    out[p] = { fade: v.fade != null ? v.fade : '', delay: v.delay != null ? v.delay : '' };
  }
  return out;
}

/** Migrates + compiles a show to OSC command lines. Throws if the selection has no cues. */
function compileShow(api, { project, defaults, selection }) {
  const migrated = api.migrateState(project);
  if (!migrated || !Array.isArray(migrated.songs)) throw new Error('invalid project');
  api.setState(migrated);
  api.setDefaults(defaults ? normalizeDefaults(defaults) : api.makeDefaults());

  let songs;
  if (selection === 'current') {
    const active = migrated.songs.find((s) => s.id === migrated.activeSongId) || migrated.songs[0];
    songs = active && Array.isArray(active.cues) && active.cues.length ? [active] : [];
  } else {
    songs = migrated.songs.filter((s) => Array.isArray(s.cues) && s.cues.length);
  }
  if (songs.length === 0) throw new Error('no cues to send');
  // buildCmdLines returns a vm-realm Array (different Array.prototype than the host),
  // which breaks assert.deepStrictEqual. Marshal back to a host string array.
  return Array.from(api.buildCmdLines(songs)).map(String);
}

module.exports = { createCompiler, compileShow, normalizeDefaults };
```

- [ ] **Step 4: Run, verify it passes.** Expected: all 4 `compile-bridge` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add hub/src/compile-bridge.js hub/test/compile-bridge.test.js
git commit -m "feat(hub): compile-bridge runs web/js/compile.js in a Node VM"
```

---

## Task 5: WebSocket server (protocol) + entrypoint

**Files:**
- Create: `hub/src/server.js`
- Create: `hub/src/index.js`

- [ ] **Step 1: Write `hub/src/server.js`**

```javascript
'use strict';
const { WebSocketServer } = require('ws');
const { OscSender } = require('./osc');
const { createCompiler, compileShow } = require('./compile-bridge');

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Starts the hub WebSocket server. Returns { wss, close() }.
 * One shared compiler context + one UDP sender are reused across connections.
 */
function startServer(config) {
  const api = createCompiler({ webJsDir: config.webJsDir });
  const sender = new OscSender({ host: config.ma3Host, port: config.ma3Port, prefix: config.ma3Prefix });
  const wss = new WebSocketServer({ host: config.host, port: config.port });

  const send = (ws, obj) => { try { ws.send(JSON.stringify(obj)); } catch { /* socket gone */ } };

  async function relayLines(ws, lines) {
    for (let i = 0; i < lines.length; i++) {
      await sender.send(lines[i]);
      send(ws, { type: 'progress', sent: i + 1, total: lines.length });
      if (i < lines.length - 1) await delay(config.intervalMs);
    }
    send(ws, { type: 'done', total: lines.length });
  }

  wss.on('connection', (ws) => {
    ws.on('message', async (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); }
      catch { return send(ws, { type: 'error', message: 'invalid JSON' }); }

      if (msg.type === 'compile-send') {
        let lines;
        try {
          lines = compileShow(api, {
            project: msg.project, defaults: msg.defaults, selection: msg.selection || 'all',
          });
        } catch (e) {
          return send(ws, { type: 'error', message: e.message });
        }
        try { await relayLines(ws, lines); }
        catch (e) { send(ws, { type: 'error', message: e.message }); }
      } else if (msg.type === 'cmd' && typeof msg.line === 'string') {
        try { await sender.send(msg.line); send(ws, { type: 'sent', line: msg.line }); }
        catch (e) { send(ws, { type: 'error', message: e.message }); }
      } else if (msg.type === 'ping') {
        send(ws, { type: 'pong' });
      } else {
        send(ws, { type: 'error', message: 'unknown message' });
      }
    });
  });

  return {
    wss,
    close() {
      return new Promise((resolve) => { sender.close(); wss.close(resolve); });
    },
  };
}

module.exports = { startServer };
```

- [ ] **Step 2: Write `hub/src/index.js`**

```javascript
'use strict';
const { loadConfig } = require('./config');
const { startServer } = require('./server');

const config = loadConfig();
const { wss } = startServer(config);

wss.on('listening', () => {
  console.log(`[hub] WebSocket listening on ws://${config.host}:${config.port}`);
  console.log(`[hub] OSC target: udp://${config.ma3Host}:${config.ma3Port}  /${config.ma3Prefix}/cmd`);
  console.log('[hub] grandMA3: Menu > Network > MA Network Configuration > OSC, input UDP ' +
    `${config.ma3Port}, prefix "${config.ma3Prefix}", Echo Input = Yes`);
});

process.on('SIGINT', () => { console.log('\n[hub] shutting down'); wss.close(); process.exit(0); });
```

- [ ] **Step 3: Smoke-run the server manually** (optional sanity)

Run: `cd hub && timeout 2 node src/index.js || true`
Expected: prints the `[hub] WebSocket listening …` lines (then exits via timeout).

- [ ] **Step 4: Commit**

```bash
git add hub/src/server.js hub/src/index.js
git commit -m "feat(hub): WebSocket server (compile-send protocol) + entrypoint"
```

---

## Task 6: Integration test — compile-send → real datagrams match the golden

Runs the actual server, connects a real WebSocket client, sends `compile-send` with `SONG_1.json`, captures the UDP datagrams on a fake listener, and asserts every datagram decodes to the golden line.

**Files:**
- Create: `hub/test/server.test.js`

- [ ] **Step 1: Write the test `hub/test/server.test.js`**

```javascript
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const dgram = require('node:dgram');
const { startServer } = require('../src/server');

const repo = path.resolve(__dirname, '..', '..');
const golden = fs.readFileSync(path.join(repo, 'examples', 'SONG_1.cmdlines.txt'), 'utf8')
  .split('\n').filter((l) => l.length > 0);
const song1 = JSON.parse(fs.readFileSync(path.join(repo, 'examples', 'SONG_1.json'), 'utf8'));

function decodeOscString(buf, offset) {
  let end = offset;
  while (buf[end] !== 0) end++;
  const s = buf.toString('utf8', offset, end);
  const len = end - offset + 1;
  const next = offset + Math.ceil(len / 4) * 4;
  return [s, next];
}
function decodeOscMessage(buf) {
  const [addr, o1] = decodeOscString(buf, 0);
  const [, o2] = decodeOscString(buf, o1); // typetag
  const [arg] = decodeOscString(buf, o2);
  return { addr, arg };
}

test('compile-send relays datagrams that decode to the golden lines', async () => {
  // Fake MA3: a UDP listener on an ephemeral port.
  const rx = dgram.createSocket('udp4');
  const datagrams = [];
  rx.on('message', (m) => datagrams.push(Buffer.from(m)));
  await new Promise((r) => rx.bind(0, '127.0.0.1', r));
  const ma3Port = rx.address().port;

  const handle = startServer({
    host: '127.0.0.1', port: 0,
    ma3Host: '127.0.0.1', ma3Port, ma3Prefix: 'gma3',
    intervalMs: 1,
  });
  await new Promise((r) => handle.wss.on('listening', r));
  const wsPort = handle.wss.address().port;

  const ws = new WebSocket(`ws://127.0.0.1:${wsPort}`);
  const progress = [];
  const done = new Promise((resolve, reject) => {
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.type === 'progress') progress.push(msg.sent);
      else if (msg.type === 'done') resolve(msg);
      else if (msg.type === 'error') reject(new Error(msg.message));
    });
  });
  await new Promise((r) => ws.addEventListener('open', r));
  ws.send(JSON.stringify({ type: 'compile-send', project: song1, selection: 'all' }));

  const doneMsg = await done;
  await new Promise((r) => setTimeout(r, 100)); // let last datagram land
  ws.close();
  await handle.close();
  rx.close();

  assert.strictEqual(doneMsg.total, golden.length);
  assert.strictEqual(datagrams.length, golden.length);
  assert.deepStrictEqual(progress, golden.map((_, i) => i + 1));
  const decoded = datagrams.map(decodeOscMessage);
  assert.ok(decoded.every((d) => d.addr === '/gma3/cmd'));
  assert.deepStrictEqual(decoded.map((d) => d.arg), golden);
});

test('compile-send with empty selection returns an error', async () => {
  const handle = startServer({
    host: '127.0.0.1', port: 0, ma3Host: '127.0.0.1', ma3Port: 9, ma3Prefix: 'gma3', intervalMs: 1,
  });
  await new Promise((r) => handle.wss.on('listening', r));
  const ws = new WebSocket(`ws://127.0.0.1:${handle.wss.address().port}`);
  const result = new Promise((resolve, reject) => {
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.type === 'error') resolve(msg);
      else if (msg.type === 'done') reject(new Error('unexpected done'));
    });
  });
  await new Promise((r) => ws.addEventListener('open', r));
  const empty = { songs: [{ id: 's1', name: '', sequence: 1, cues: [] }], activeSongId: 's1', storeMode: 'Overwrite' };
  ws.send(JSON.stringify({ type: 'compile-send', project: empty, selection: 'all' }));
  const msg = await result;
  assert.match(msg.message, /no cues/);
  ws.close();
  await handle.close();
});
```

- [ ] **Step 2: Run the full suite, verify it passes**

Run: `cd hub && npm test`
Expected: all suites PASS (`config`, `osc`, `compile-bridge`, `server`).

- [ ] **Step 3: Commit**

```bash
git add hub/test/server.test.js
git commit -m "test(hub): integration — compile-send datagrams match golden fixture"
```

---

## Task 7: Run docs + Pi service notes

**Files:**
- Create: `hub/README.md`
- Create: `hub/deploy/cuelist-hub.service`

- [ ] **Step 1: Write `hub/README.md`**

````markdown
# Cuelist Compiler — Pi Hub

Receives a show from the iPhone over WebSocket, compiles it with the real
`web/js/compile.js`, and relays the MA3 command sequence as OSC/UDP.

## Run

```bash
cd hub
npm install
npm start
```

Configure via env:

| Var | Default | Meaning |
|-----|---------|---------|
| `HUB_HOST` | `0.0.0.0` | WS bind host |
| `HUB_PORT` | `9000` | WS port the phone connects to |
| `MA3_HOST` | `127.0.0.1` | grandMA3 IP |
| `MA3_PORT` | `8000` | MA3 OSC input UDP port |
| `MA3_PREFIX` | `gma3` | OSC prefix → address `/<prefix>/cmd` |
| `OSC_INTERVAL_MS` | `20` | throttle between lines |
| `WEB_JS_DIR` | `../web/js` | location of the web compiler modules |

grandMA3: **Menu > Network > MA Network Configuration > OSC** — input UDP `8000`,
prefix `gma3`, **Echo Input = Yes** (required for `/cmd` to dispatch).

## Protocol

```
→ { type: "compile-send", project, defaults, selection: "current"|"all" }
← { type: "progress", sent, total } | { type: "done", total } | { type: "error", message }
```

Remote use: reach the Pi over a private tunnel (Tailscale/WireGuard) and point the
phone at the Pi's tunnel address instead of its LAN IP.
````

- [ ] **Step 2: Write `hub/deploy/cuelist-hub.service`** (systemd unit for the Pi)

```ini
[Unit]
Description=Cuelist Compiler Pi Hub
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/home/pi/cuelist-compiler/hub
ExecStart=/usr/bin/node src/index.js
Environment=HUB_PORT=9000
Environment=MA3_HOST=127.0.0.1
Environment=MA3_PORT=8000
Environment=MA3_PREFIX=gma3
Restart=on-failure
User=pi

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 3: Final full-suite run**

Run: `cd hub && npm test`
Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add hub/README.md hub/deploy/cuelist-hub.service
git commit -m "docs(hub): run instructions + systemd unit for the Pi"
```

---

## Done criteria for Plan A

- `cd hub && npm test` green across `config`, `osc`, `compile-bridge`, `server`.
- `examples/SONG_1.cmdlines.txt` exists and matches the JS reference (18 lines).
- A real `compile-send` of `SONG_1.json` produces UDP datagrams that decode exactly
  to the golden lines — proving compile (via `compile.js`) + OSC encode + relay end to end.
- No changes to `web/` or `proxy/`.
- `npm start` boots the hub; ready to run on the Pi as a systemd service.

**Next:** Plan B — iOS app (native authoring UI + `ProjectStore` + `HubClient`
speaking this protocol). The phone-side carries over the models/migration/store from
the superseded engine plan; the send path is now "serialize show → `compile-send` →
stream progress" against this hub.
