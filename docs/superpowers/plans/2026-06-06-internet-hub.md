# Internet Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the iPhone drive the grandMA3 desk over the internet (cellular/any network) by pairing with a stripped-down laptop **menubar hub** through a small **Fly relay**, paired by a shared code.

**Architecture:** Both phone and laptop dial *out* over `wss://…fly.dev` to a dumb pairing relay that forwards JSON between the one hub and one phone sharing a pairing code. The laptop runs the existing `hub/src/*` compile/OSC core (extracted into a transport-agnostic `handleMessage`) and relays each command to the desk over OSC/UDP. Relay-only v1; kept entirely out of `desktop/`.

**Tech Stack:** Node + `ws` (relay + menubar main/relay-client), Electron tray+popover (menubar UI), Fly.io (relay host), Swift/SwiftUI + `URLSessionWebSocketTask` (iOS additive relay mode).

---

## File Structure

```
hub/
  src/handle.js          NEW — transport-agnostic createContext() + handleMessage()
  src/server.js          MODIFY — delegate to handle.js (behavior unchanged)
  test/handle.test.js    NEW — direct tests for handleMessage

relay/                   NEW Fly app
  src/rooms.js           pure pairing state machine (testable with fake sockets)
  src/server.js          ws + http(/healthz) wiring + heartbeat
  src/index.js           entrypoint (reads PORT)
  test/rooms.test.js     pairing unit tests
  package.json  Dockerfile  fly.toml  .dockerignore  README.md

menubar-hub/             NEW Electron tray app
  src/settings.js        settings + pairing-code gen (mirrors desktop/settings.js)
  src/relay-client.js    dials relay, joins as hub, runs handleMessage, emits log
  main.js                Electron tray + popover window + IPC
  preload.js             contextBridge API for the renderer
  renderer/index.html    popover markup
  renderer/styles.css    styled status + log
  renderer/app.js        renderer logic (status, pairing code, settings, log feed)
  test/settings.test.js  settings + pairing-code unit tests
  test/relay-client.test.js  relay-client unit tests (fake socket)
  package.json  README.md

ios/Sources/Kit/Hub/
  HubMessages.swift      MODIFY — add join/peer frames
  HubClient.swift        MODIFY — connection mode (direct|relay) + join handshake
ios/Sources/App/
  SettingsView.swift     MODIFY — mode toggle + relay fields
ios/Tests/KitTests/
  RelayModeTests.swift   NEW — message + HubClient relay-mode tests
```

---

## PHASE A — Shared core: extract `handleMessage` from `hub/`

### Task A1: Extract transport-agnostic `handleMessage` + `createContext`

**Files:**
- Create: `hub/src/handle.js`
- Create: `hub/test/handle.test.js`
- Modify: `hub/src/server.js`

- [ ] **Step 1: Write the failing test** — `hub/test/handle.test.js`

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const { createContext, handleMessage } = require('../src/handle');

// A fake OSC sender that records lines instead of opening a UDP socket.
function fakeCtx() {
  const sent = [];
  const ctx = {
    api: null,
    sender: { send: (line) => { sent.push(line); return Promise.resolve(); }, close() {} },
    config: { intervalMs: 0, ma3Host: '127.0.0.1', ma3Port: 8000, ma3Prefix: 'gma3' },
  };
  return { ctx, sent };
}

test('cmd: sends the line and replies {sent}', async () => {
  const { ctx, sent } = fakeCtx();
  const frames = [];
  const out = await handleMessage(ctx, { type: 'cmd', line: 'Go+' }, (o) => frames.push(o));
  assert.deepStrictEqual(sent, ['Go+']);
  assert.deepStrictEqual(frames, [{ type: 'sent', line: 'Go+' }]);
  assert.deepStrictEqual(out, { kind: 'cmd', summary: 'Go+' });
});

test('ping: replies {pong}', async () => {
  const { ctx } = fakeCtx();
  const frames = [];
  await handleMessage(ctx, { type: 'ping' }, (o) => frames.push(o));
  assert.deepStrictEqual(frames, [{ type: 'pong' }]);
});

test('unknown: replies {error}', async () => {
  const { ctx } = fakeCtx();
  const frames = [];
  const out = await handleMessage(ctx, { type: 'bogus' }, (o) => frames.push(o));
  assert.strictEqual(frames[0].type, 'error');
  assert.strictEqual(out.kind, 'error');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd hub && node --test test/handle.test.js`
Expected: FAIL — `Cannot find module '../src/handle'`.

- [ ] **Step 3: Write `hub/src/handle.js`**

```js
'use strict';
// Transport-agnostic core: turns one parsed phone message into OSC side effects +
// reply frames. Used by both the LAN WebSocket server (hub/src/server.js) and the
// Fly relay client (menubar-hub/src/relay-client.js). `reply(obj)` sends one JSON
// frame back toward the phone; the return value summarizes the action for logging.
const { createCompiler, compileShow } = require('./compile-bridge');
const { OscSender } = require('./osc');
const { pullSequences } = require('./pull');

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

/** Build the shared per-process context: one VM compiler + one UDP sender. */
function createContext(config) {
  const api = createCompiler({ webJsDir: config.webJsDir });
  const sender = new OscSender({ host: config.ma3Host, port: config.ma3Port, prefix: config.ma3Prefix });
  return { api, sender, config };
}

async function handleMessage(ctx, msg, reply) {
  const { api, sender, config } = ctx;

  if (msg.type === 'compile-send') {
    let lines;
    try {
      lines = compileShow(api, {
        project: msg.project, defaults: msg.defaults, selection: msg.selection || 'all',
      });
    } catch (e) { reply({ type: 'error', message: e.message }); return { kind: 'error', summary: e.message }; }
    try {
      for (let i = 0; i < lines.length; i++) {
        await sender.send(lines[i]);
        reply({ type: 'progress', sent: i + 1, total: lines.length });
        if (i < lines.length - 1) await delay(config.intervalMs);
      }
      reply({ type: 'done', total: lines.length });
      return { kind: 'send', summary: `${msg.selection || 'all'} → ${lines.length} lines` };
    } catch (e) { reply({ type: 'error', message: e.message }); return { kind: 'error', summary: e.message }; }
  }

  if (msg.type === 'cmd' && typeof msg.line === 'string') {
    try { await sender.send(msg.line); reply({ type: 'sent', line: msg.line }); return { kind: 'cmd', summary: msg.line }; }
    catch (e) { reply({ type: 'error', message: e.message }); return { kind: 'error', summary: e.message }; }
  }

  if (msg.type === 'pull-sequences') {
    try {
      const data = await pullSequences({
        sender, trigger: config.pullTrigger, file: config.pullFile, timeoutMs: config.pullTimeoutMs,
      });
      reply({ type: 'sequences', version: data.version ?? 1, sequences: data.sequences });
      return { kind: 'pull', summary: `${data.sequences.length} sequences` };
    } catch (e) { reply({ type: 'pull-error', message: e.message }); return { kind: 'error', summary: e.message }; }
  }

  if (msg.type === 'ping') { reply({ type: 'pong' }); return { kind: 'ping', summary: 'ping' }; }

  reply({ type: 'error', message: 'unknown message' });
  return { kind: 'error', summary: 'unknown message' };
}

module.exports = { createContext, handleMessage };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd hub && node --test test/handle.test.js`
Expected: PASS — 3 tests.

- [ ] **Step 5: Rewire `hub/src/server.js` to delegate**

Replace the body of `startServer` so it builds the context via `createContext` and calls `handleMessage` per message. New full file:

```js
'use strict';
const { WebSocketServer } = require('ws');
const { createContext, handleMessage } = require('./handle');

/**
 * Starts the hub WebSocket server. Returns { wss, close() }.
 * One shared compiler context + one UDP sender are reused across connections.
 */
function startServer(config) {
  const ctx = createContext(config);
  const wss = new WebSocketServer({ host: config.host, port: config.port });

  const send = (ws, obj) => { try { ws.send(JSON.stringify(obj)); } catch { /* socket gone */ } };

  wss.on('connection', (ws) => {
    ws.on('message', async (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); }
      catch { return send(ws, { type: 'error', message: 'invalid JSON' }); }
      await handleMessage(ctx, msg, (obj) => send(ws, obj));
    });
  });

  return {
    wss,
    close() {
      return new Promise((resolve) => {
        for (const client of wss.clients) client.terminate();
        ctx.sender.close();
        wss.close(resolve);
      });
    },
  };
}

module.exports = { startServer };
```

- [ ] **Step 6: Run the whole hub suite to verify no regression**

Run: `cd hub && npm install && npm test`
Expected: PASS — existing `server.test.js`, `compile-bridge.test.js`, `osc.test.js`, `pull.test.js`, `config.test.js` all green, plus the new `handle.test.js`.

- [ ] **Step 7: Commit**

```bash
git add hub/src/handle.js hub/test/handle.test.js hub/src/server.js
git commit -m "refactor(hub): extract transport-agnostic handleMessage core"
```

---

## PHASE B — The Fly relay (`relay/`)

### Task B1: Pairing state machine (`relay/src/rooms.js`)

**Files:**
- Create: `relay/src/rooms.js`
- Create: `relay/test/rooms.test.js`
- Create: `relay/package.json`

- [ ] **Step 1: Create `relay/package.json`**

```json
{
  "name": "cuelist-relay",
  "version": "0.1.0",
  "private": true,
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

- [ ] **Step 2: Write the failing test** — `relay/test/rooms.test.js`

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const { Rooms } = require('../src/rooms');

// Fake socket: records every string passed to .send().
function fakeSocket() { const out = []; return { out, send: (s) => out.push(JSON.parse(s)) }; }

test('matching code bridges hub and phone, both told peer connected', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), phone = fakeSocket();
  assert.deepStrictEqual(rooms.join(hub, 'ABC12345', 'hub'), { ok: true });
  assert.deepStrictEqual(hub.out, [{ type: 'joined' }]);
  assert.deepStrictEqual(rooms.join(phone, 'ABC12345', 'phone'), { ok: true });
  // phone gets joined + peer; hub gets a peer-connected too
  assert.deepStrictEqual(phone.out, [{ type: 'joined' }, { type: 'peer', connected: true }]);
  assert.deepStrictEqual(hub.out, [{ type: 'joined' }, { type: 'peer', connected: true }]);
});

test('forward relays raw text verbatim to the peer only', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), phone = fakeSocket();
  rooms.join(hub, 'ROOMCODE1', 'hub');
  rooms.join(phone, 'ROOMCODE1', 'phone');
  hub.out.length = 0; phone.out.length = 0;
  rooms.forward(phone, JSON.stringify({ type: 'cmd', line: 'Go+' }));
  assert.deepStrictEqual(hub.out, [{ type: 'cmd', line: 'Go+' }]);
  assert.deepStrictEqual(phone.out, []);
});

test('second hub in a full room is rejected', () => {
  const rooms = new Rooms();
  rooms.join(fakeSocket(), 'ROOMCODE1', 'hub');
  assert.deepStrictEqual(rooms.join(fakeSocket(), 'ROOMCODE1', 'hub'), { ok: false, error: 'role taken' });
});

test('mismatched codes never bridge', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), phone = fakeSocket();
  rooms.join(hub, 'CODE-AAAA', 'hub');
  rooms.join(phone, 'CODE-BBBB', 'phone');
  rooms.forward(phone, JSON.stringify({ type: 'cmd', line: 'Go+' }));
  assert.deepStrictEqual(hub.out, [{ type: 'joined' }]); // never received the cmd
});

test('leave notifies the surviving peer', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), phone = fakeSocket();
  rooms.join(hub, 'ROOMCODE1', 'hub');
  rooms.join(phone, 'ROOMCODE1', 'phone');
  hub.out.length = 0;
  rooms.leave(phone);
  assert.deepStrictEqual(hub.out, [{ type: 'peer', connected: false }]);
});

test('too-short code is rejected', () => {
  const rooms = new Rooms();
  assert.deepStrictEqual(rooms.join(fakeSocket(), 'short', 'hub'), { ok: false, error: 'bad room' });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd relay && npm install && node --test test/rooms.test.js`
Expected: FAIL — `Cannot find module '../src/rooms'`.

- [ ] **Step 4: Write `relay/src/rooms.js`**

```js
'use strict';
// Pure pairing logic — no network. A "socket" is any object with .send(string).
// One hub + one phone share a room keyed by the pairing code; everything else is
// forwarded verbatim to the opposite role.

const MIN_CODE_LEN = 6;

class Rooms {
  constructor({ maxRooms = 200 } = {}) {
    this.maxRooms = maxRooms;
    this.rooms = new Map(); // code -> { hub, phone }
  }

  join(socket, code, role) {
    if (role !== 'hub' && role !== 'phone') return { ok: false, error: 'bad role' };
    if (typeof code !== 'string' || code.length < MIN_CODE_LEN) return { ok: false, error: 'bad room' };

    let room = this.rooms.get(code);
    if (!room) {
      if (this.rooms.size >= this.maxRooms) return { ok: false, error: 'relay full' };
      room = { hub: null, phone: null };
      this.rooms.set(code, room);
    }
    if (room[role]) return { ok: false, error: 'role taken' };

    room[role] = socket;
    socket._room = code;
    socket._role = role;
    socket.send(JSON.stringify({ type: 'joined' }));

    const peer = room[role === 'hub' ? 'phone' : 'hub'];
    if (peer) {
      socket.send(JSON.stringify({ type: 'peer', connected: true }));
      peer.send(JSON.stringify({ type: 'peer', connected: true }));
    }
    return { ok: true };
  }

  forward(socket, rawText) {
    const code = socket._room;
    if (!code) return;
    const room = this.rooms.get(code);
    if (!room) return;
    const peer = room[socket._role === 'hub' ? 'phone' : 'hub'];
    if (peer) peer.send(rawText);
  }

  leave(socket) {
    const code = socket._room;
    if (!code) return;
    const room = this.rooms.get(code);
    if (!room) return;
    if (room[socket._role] === socket) room[socket._role] = null;
    const peer = room[socket._role === 'hub' ? 'phone' : 'hub'];
    if (peer) peer.send(JSON.stringify({ type: 'peer', connected: false }));
    if (!room.hub && !room.phone) this.rooms.delete(code);
  }
}

module.exports = { Rooms, MIN_CODE_LEN };
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd relay && node --test test/rooms.test.js`
Expected: PASS — 6 tests.

- [ ] **Step 6: Commit**

```bash
git add relay/package.json relay/src/rooms.js relay/test/rooms.test.js
git commit -m "feat(relay): pairing state machine"
```

### Task B2: Relay server wiring (`relay/src/server.js` + `index.js`)

**Files:**
- Create: `relay/src/server.js`
- Create: `relay/src/index.js`
- Create: `relay/test/server.test.js`

- [ ] **Step 1: Write the failing test** — `relay/test/server.test.js`

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const WebSocket = require('ws');
const { startRelay } = require('../src/server');

function open(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.once('open', () => resolve(ws));
    ws.once('error', reject);
  });
}
function nextMsg(ws) {
  return new Promise((resolve) => ws.once('message', (m) => resolve(JSON.parse(m.toString()))));
}

test('two clients with the same code exchange a forwarded frame end to end', async () => {
  const relay = startRelay({ port: 0 });
  const port = relay.server.address().port;
  const url = `ws://127.0.0.1:${port}`;

  const hub = await open(url);
  hub.send(JSON.stringify({ type: 'join', room: 'ENDTOEND1', role: 'hub' }));
  assert.deepStrictEqual(await nextMsg(hub), { type: 'joined' });

  const phone = await open(url);
  phone.send(JSON.stringify({ type: 'join', room: 'ENDTOEND1', role: 'phone' }));
  assert.deepStrictEqual(await nextMsg(phone), { type: 'joined' });
  assert.deepStrictEqual(await nextMsg(phone), { type: 'peer', connected: true });
  assert.deepStrictEqual(await nextMsg(hub), { type: 'peer', connected: true });

  phone.send(JSON.stringify({ type: 'cmd', line: 'Go+' }));
  assert.deepStrictEqual(await nextMsg(hub), { type: 'cmd', line: 'Go+' });

  hub.close(); phone.close();
  await relay.close();
});

test('a socket that never joins is closed', async () => {
  const relay = startRelay({ port: 0, joinTimeoutMs: 100 });
  const port = relay.server.address().port;
  const ws = await open(`ws://127.0.0.1:${port}`);
  const closed = new Promise((resolve) => ws.once('close', resolve));
  await closed; // closes within joinTimeoutMs without a join frame
  await relay.close();
});

test('GET /healthz returns 200', async () => {
  const relay = startRelay({ port: 0 });
  const port = relay.server.address().port;
  const body = await new Promise((resolve) => {
    require('node:http').get(`http://127.0.0.1:${port}/healthz`, (res) => {
      let b = ''; res.on('data', (d) => (b += d)); res.on('end', () => resolve({ status: res.statusCode, b }));
    });
  });
  assert.strictEqual(body.status, 200);
  await relay.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd relay && node --test test/server.test.js`
Expected: FAIL — `Cannot find module '../src/server'`.

- [ ] **Step 3: Write `relay/src/server.js`**

```js
'use strict';
const http = require('node:http');
const { WebSocketServer } = require('ws');
const { Rooms } = require('./rooms');

const MAX_FRAME = 256 * 1024;        // 256 KB cap — shows are small JSON
const DEFAULT_JOIN_TIMEOUT_MS = 5000;
const HEARTBEAT_MS = 25000;          // keep Fly from idling the socket

function startRelay({ port, host = '0.0.0.0', joinTimeoutMs = DEFAULT_JOIN_TIMEOUT_MS } = {}) {
  const rooms = new Rooms();

  const server = http.createServer((req, res) => {
    if (req.url === '/healthz') { res.writeHead(200); res.end('ok'); return; }
    res.writeHead(426); res.end('upgrade required');
  });
  const wss = new WebSocketServer({ server, maxPayload: MAX_FRAME });

  wss.on('connection', (ws) => {
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });

    let joined = false;
    const joinTimer = setTimeout(() => { if (!joined) ws.close(); }, joinTimeoutMs);

    ws.on('message', (raw) => {
      const text = raw.toString();
      if (!joined) {
        let msg;
        try { msg = JSON.parse(text); } catch { return ws.close(); }
        if (msg.type !== 'join') return ws.close();
        const res = rooms.join(ws, msg.room, msg.role);
        if (!res.ok) { try { ws.send(JSON.stringify({ type: 'join-error', message: res.error })); } catch {} return ws.close(); }
        joined = true;
        clearTimeout(joinTimer);
        return;
      }
      rooms.forward(ws, text);  // opaque passthrough
    });

    ws.on('close', () => { clearTimeout(joinTimer); rooms.leave(ws); });
    ws.on('error', () => { /* a 'close' will follow */ });
  });

  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (ws.isAlive === false) { ws.terminate(); continue; }
      ws.isAlive = false;
      try { ws.ping(); } catch {}
    }
  }, HEARTBEAT_MS);

  server.listen(port, host);

  return {
    server, wss, rooms,
    close() {
      clearInterval(heartbeat);
      return new Promise((resolve) => { wss.close(() => server.close(resolve)); });
    },
  };
}

module.exports = { startRelay };
```

- [ ] **Step 4: Write `relay/src/index.js`**

```js
'use strict';
const { startRelay } = require('./server');

const port = parseInt(process.env.PORT || '8080', 10);
const relay = startRelay({ port });
relay.server.on('listening', () => {
  console.log(`[relay] listening on :${port} (ws upgrade + GET /healthz)`);
});

process.on('SIGINT', () => { console.log('\n[relay] shutting down'); relay.close().then(() => process.exit(0)); });
process.on('SIGTERM', () => { relay.close().then(() => process.exit(0)); });
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd relay && node --test`
Expected: PASS — `rooms.test.js` + `server.test.js` all green.

- [ ] **Step 6: Commit**

```bash
git add relay/src/server.js relay/src/index.js relay/test/server.test.js
git commit -m "feat(relay): ws + http(/healthz) server with join/forward + heartbeat"
```

### Task B3: Fly packaging + deploy

**Files:**
- Create: `relay/Dockerfile`
- Create: `relay/.dockerignore`
- Create: `relay/fly.toml`
- Create: `relay/README.md`

- [ ] **Step 1: Write `relay/Dockerfile`**

```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --omit=dev
COPY src ./src
ENV PORT=8080
EXPOSE 8080
CMD ["node", "src/index.js"]
```

- [ ] **Step 2: Write `relay/.dockerignore`**

```
node_modules
test
*.md
```

- [ ] **Step 3: Write `relay/fly.toml`** (one machine, never auto-stop — the laptop holds a persistent socket)

```toml
app = "cuelist-relay"
primary_region = "ams"

[build]

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = false
  auto_start_machines = true
  min_machines_running = 1

  [[http_service.checks]]
    interval = "15s"
    timeout = "2s"
    grace_period = "5s"
    method = "GET"
    path = "/healthz"

[[vm]]
  size = "shared-cpu-1x"
  memory = "256mb"
```

- [ ] **Step 4: Write `relay/README.md`**

````markdown
# Cuelist Compiler — Internet Relay

A tiny stateless WebSocket pairer on Fly.io. The laptop **menubar hub** and the
iPhone both dial out to it and present a shared **pairing code**; the relay
forwards JSON between the one hub and one phone in that room. It never parses OSC
and never sees your LAN.

```
iPhone  ──wss──►  cuelist-relay (this)  ◄──wss──  menubar hub (laptop) ──OSC──► grandMA3
```

## Protocol

First frame from each side:

```json
{ "type": "join", "room": "<pairingCode>", "role": "hub" | "phone" }
```

Relay replies `{ "type": "joined" }`, then `{ "type": "peer", "connected": true|false }`
whenever the other side connects/drops. Every later frame is forwarded verbatim
to the opposite role. A socket that doesn't `join` within 5s is closed; frames
are capped at 256 KB; rooms are capped.

## Deploy

```sh
cd relay
fly launch --no-deploy --name cuelist-relay   # first time: creates the app from fly.toml
fly deploy
```

Health: `GET https://cuelist-relay.fly.dev/healthz` → `ok`.
The phone/laptop connect to `wss://cuelist-relay.fly.dev`.

> One machine, `min_machines_running = 1` (the laptop holds a persistent
> connection — don't let Fly stop it). Never run two `fly deploy` at once.

## Test

```sh
cd relay && npm install && npm test
```
````

- [ ] **Step 5: Generate the lockfile (so the Docker build is reproducible)**

Run: `cd relay && npm install --package-lock-only`
Expected: `relay/package-lock.json` created.

- [ ] **Step 6: Deploy to Fly and verify health**

Run (manual — needs the user's Fly auth):
```bash
cd relay
fly launch --no-deploy --name cuelist-relay --region ams
fly deploy
curl -fsS https://cuelist-relay.fly.dev/healthz
```
Expected: `ok`. (If `fly launch` prompts to overwrite `fly.toml`, decline — keep ours.)

- [ ] **Step 7: Commit**

```bash
git add relay/Dockerfile relay/.dockerignore relay/fly.toml relay/README.md relay/package-lock.json
git commit -m "feat(relay): Fly packaging + deploy docs"
```

---

## PHASE C — The menubar hub app (`menubar-hub/`)

### Task C1: Settings module + pairing-code generation

**Files:**
- Create: `menubar-hub/package.json`
- Create: `menubar-hub/src/settings.js`
- Create: `menubar-hub/test/settings.test.js`

- [ ] **Step 1: Write `menubar-hub/package.json`**

```json
{
  "name": "cuelist-menubar-hub",
  "version": "0.1.0",
  "private": true,
  "description": "Stripped-down laptop hub: pairs with the iPhone over a Fly relay and relays OSC to grandMA3.",
  "main": "main.js",
  "scripts": {
    "start": "electron .",
    "test": "node --test test/"
  },
  "dependencies": {
    "ws": "^8.18.0"
  },
  "devDependencies": {
    "electron": "^31.0.0"
  }
}
```

- [ ] **Step 2: Write the failing test** — `menubar-hub/test/settings.test.js`

```js
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

test('generatePairingCode is url-safe and >= 8 chars', () => {
  const code = generatePairingCode();
  assert.ok(/^[A-Za-z0-9_-]{8,}$/.test(code), `unexpected code: ${code}`);
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
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd menubar-hub && node --test test/settings.test.js`
Expected: FAIL — `Cannot find module '../src/settings'`.

- [ ] **Step 4: Write `menubar-hub/src/settings.js`**

```js
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd menubar-hub && node --test test/settings.test.js`
Expected: PASS — 5 tests.

- [ ] **Step 6: Commit**

```bash
git add menubar-hub/package.json menubar-hub/src/settings.js menubar-hub/test/settings.test.js
git commit -m "feat(menubar-hub): settings module + pairing-code generation"
```

### Task C2: Relay client (`menubar-hub/src/relay-client.js`)

**Files:**
- Create: `menubar-hub/src/relay-client.js`
- Create: `menubar-hub/test/relay-client.test.js`

- [ ] **Step 1: Write the failing test** — `menubar-hub/test/relay-client.test.js`

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const { EventEmitter } = require('node:events');
const { RelayHubClient } = require('../src/relay-client');

// A fake WebSocket: captures sends, lets the test drive open/message/close.
class FakeSocket extends EventEmitter {
  constructor() { super(); this.sent = []; this.readyState = 1; }
  send(s) { this.sent.push(JSON.parse(s)); }
  close() { this.emit('close'); }
  ping() {}
}

// A fake ctx so no real OSC/VM is built; handleMessage is stubbed via the injected core.
function fakeDeps() {
  const osc = [];
  const core = {
    createContext: () => ({ sender: { close() {} } }),
    handleMessage: async (_ctx, msg, reply) => {
      if (msg.type === 'cmd') { osc.push(msg.line); reply({ type: 'sent', line: msg.line }); return { kind: 'cmd', summary: msg.line }; }
      return { kind: 'other', summary: '' };
    },
  };
  return { osc, core };
}

const config = { relayUrl: 'wss://x', pairingCode: 'CODE1234', ma3Host: '127.0.0.1', ma3Port: 8000, ma3Prefix: 'gma3', intervalMs: 0 };

test('on open it sends a hub join frame', () => {
  const sock = new FakeSocket();
  const { core } = fakeDeps();
  const c = new RelayHubClient(config, {}, { makeSocket: () => sock, core });
  c.connect();
  sock.emit('open');
  assert.deepStrictEqual(sock.sent[0], { type: 'join', room: 'CODE1234', role: 'hub' });
});

test('peer frame drives onPeer; phone cmd reaches OSC and replies via the socket', async () => {
  const sock = new FakeSocket();
  const { osc, core } = fakeDeps();
  const peers = []; const logs = [];
  const c = new RelayHubClient(config, { onPeer: (b) => peers.push(b), onLog: (e) => logs.push(e) },
    { makeSocket: () => sock, core });
  c.connect();
  sock.emit('open');
  sock.emit('message', Buffer.from(JSON.stringify({ type: 'peer', connected: true })));
  assert.deepStrictEqual(peers, [true]);

  sock.emit('message', Buffer.from(JSON.stringify({ type: 'cmd', line: 'Go+' })));
  await new Promise((r) => setTimeout(r, 0));   // let the async handler settle
  assert.deepStrictEqual(osc, ['Go+']);
  // reply went back out over the relay socket
  assert.ok(sock.sent.some((m) => m.type === 'sent' && m.line === 'Go+'));
  // and a log entry was emitted
  assert.ok(logs.some((e) => e.kind === 'cmd' && e.summary === 'Go+'));
});

test('control frames (joined/peer) are NOT forwarded to handleMessage', async () => {
  const sock = new FakeSocket();
  const { osc, core } = fakeDeps();
  const c = new RelayHubClient(config, {}, { makeSocket: () => sock, core });
  c.connect(); sock.emit('open');
  sock.emit('message', Buffer.from(JSON.stringify({ type: 'joined' })));
  await new Promise((r) => setTimeout(r, 0));
  assert.deepStrictEqual(osc, []);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd menubar-hub && node --test test/relay-client.test.js`
Expected: FAIL — `Cannot find module '../src/relay-client'`.

- [ ] **Step 3: Write `menubar-hub/src/relay-client.js`**

```js
'use strict';
const WebSocket = require('ws');
// Default core is the shared hub logic; injectable for tests.
const defaultCore = require('../../hub/src/handle');

const CONTROL_TYPES = new Set(['joined', 'peer', 'join-error']);

/**
 * Dials the relay, joins as 'hub', and runs the shared handleMessage core for every
 * phone frame, replying back over the same relay socket. Reconnects with backoff.
 *
 * hooks: { onState(string), onPeer(bool), onLog({kind,summary,at}) }
 */
class RelayHubClient {
  constructor(config, hooks = {}, { makeSocket, core } = {}) {
    this.config = config;
    this.hooks = hooks;
    this.core = core || defaultCore;
    this.makeSocket = makeSocket || ((url) => new WebSocket(url));
    this.ctx = this.core.createContext(config);
    this.ws = null;
    this.stopped = false;
    this.backoff = 1000;
    this.reconnectTimer = null;
  }

  _state(s) { this.hooks.onState && this.hooks.onState(s); }
  _peer(b) { this.hooks.onPeer && this.hooks.onPeer(b); }
  _log(entry) { this.hooks.onLog && this.hooks.onLog(entry); }

  connect() {
    this.stopped = false;
    this._state('connecting');
    const ws = this.makeSocket(this.config.relayUrl);
    this.ws = ws;

    ws.on('open', () => {
      this.backoff = 1000;
      ws.send(JSON.stringify({ type: 'join', room: this.config.pairingCode, role: 'hub' }));
      this._state('online');
    });

    ws.on('message', (raw) => this._onMessage(raw.toString()));

    ws.on('close', () => {
      this._peer(false);
      this._state('offline');
      if (!this.stopped) this._scheduleReconnect();
    });

    ws.on('error', () => { /* a 'close' follows */ });
  }

  async _onMessage(text) {
    let msg;
    try { msg = JSON.parse(text); } catch { return; }

    if (CONTROL_TYPES.has(msg.type)) {
      if (msg.type === 'peer') this._peer(!!msg.connected);
      if (msg.type === 'join-error') this._state(`error: ${msg.message}`);
      return;
    }

    const reply = (obj) => { try { this.ws.send(JSON.stringify(obj)); } catch {} };
    const out = await this.core.handleMessage(this.ctx, msg, reply);
    if (out && out.kind && out.kind !== 'ping') this._log({ ...out, at: Date.now() });
  }

  _scheduleReconnect() {
    clearTimeout(this.reconnectTimer);
    const wait = this.backoff;
    this.backoff = Math.min(this.backoff * 2, 15000);
    this.reconnectTimer = setTimeout(() => { if (!this.stopped) this.connect(); }, wait);
  }

  close() {
    this.stopped = true;
    clearTimeout(this.reconnectTimer);
    try { this.ws && this.ws.close(); } catch {}
    try { this.ctx.sender.close(); } catch {}
  }
}

module.exports = { RelayHubClient };
```

> Note: `Date.now()` here runs in the Electron process at runtime, not in a workflow script — it is allowed.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd menubar-hub && node --test test/relay-client.test.js`
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add menubar-hub/src/relay-client.js menubar-hub/test/relay-client.test.js
git commit -m "feat(menubar-hub): relay client running the shared handleMessage core"
```

### Task C3: Electron main — tray + popover window + IPC

**Files:**
- Create: `menubar-hub/main.js`
- Create: `menubar-hub/preload.js`

- [ ] **Step 1: Write `menubar-hub/preload.js`**

```js
'use strict';
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('hub', {
  getState: () => ipcRenderer.invoke('hub:getState'),
  getSettings: () => ipcRenderer.invoke('hub:getSettings'),
  setSettings: (partial) => ipcRenderer.invoke('hub:setSettings', partial),
  regenCode: () => ipcRenderer.invoke('hub:regenCode'),
  // push channels: main → renderer
  onState: (cb) => ipcRenderer.on('hub:state', (_e, s) => cb(s)),
  onPeer: (cb) => ipcRenderer.on('hub:peer', (_e, b) => cb(b)),
  onLog: (cb) => ipcRenderer.on('hub:log', (_e, entry) => cb(entry)),
});
```

- [ ] **Step 2: Write `menubar-hub/main.js`**

```js
'use strict';
const path = require('node:path');
const { app, Tray, BrowserWindow, ipcMain, nativeImage, screen } = require('electron');
const settingsModule = require('./src/settings');
const { RelayHubClient } = require('./src/relay-client');

let tray = null;
let popover = null;
let client = null;
let settings = settingsModule.defaults();
let state = { relay: 'offline', peer: false };

function buildClient() {
  if (client) client.close();
  state = { relay: 'connecting', peer: false };
  client = new RelayHubClient(settings, {
    onState: (s) => { state.relay = s; pushToRenderer('hub:state', s); updateTrayTitle(); },
    onPeer:  (b) => { state.peer = b;  pushToRenderer('hub:peer', b);  updateTrayTitle(); },
    onLog:   (e) => pushToRenderer('hub:log', e),
  });
  client.connect();
}

function pushToRenderer(channel, payload) {
  if (popover && !popover.isDestroyed()) popover.webContents.send(channel, payload);
}

function updateTrayTitle() {
  if (!tray) return;
  // Menubar glyph: ● paired, ◐ relay-up-no-phone, ○ offline.
  const glyph = state.peer ? '●' : state.relay === 'online' ? '◐' : '○';
  tray.setTitle(` ${glyph}`);
}

function createPopover() {
  popover = new BrowserWindow({
    width: 360, height: 480, show: false, frame: false, resizable: false,
    fullscreenable: false, skipTaskbar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false },
  });
  popover.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  popover.on('blur', () => { if (popover && !popover.isDestroyed()) popover.hide(); });
}

function togglePopover() {
  if (!popover) return;
  if (popover.isVisible()) { popover.hide(); return; }
  const tb = tray.getBounds();
  const wb = popover.getBounds();
  const x = Math.round(tb.x + tb.width / 2 - wb.width / 2);
  const y = Math.round(tb.y + tb.height);
  popover.setPosition(x, Math.max(y, 0), false);
  popover.show();
  popover.focus();
}

function trayIcon() {
  // Template image so macOS tints it for light/dark menubars. A 16x16 transparent
  // PNG ships at renderer/trayTemplate.png; fall back to an empty image if missing.
  const p = path.join(__dirname, 'renderer', 'trayTemplate.png');
  const img = nativeImage.createFromPath(p);
  img.setTemplateImage(true);
  return img.isEmpty() ? nativeImage.createEmpty() : img;
}

app.whenReady().then(() => {
  if (app.dock) app.dock.hide();                 // menubar-only, no dock icon
  settings = settingsModule.load(app.getPath('userData'));

  tray = new Tray(trayIcon());
  tray.setToolTip('Cuelist Internet Hub');
  tray.on('click', togglePopover);
  updateTrayTitle();

  createPopover();
  buildClient();

  ipcMain.handle('hub:getState', () => ({ ...state, pairingCode: settings.pairingCode }));
  ipcMain.handle('hub:getSettings', () => settings);
  ipcMain.handle('hub:setSettings', (_e, partial) => {
    settings = settingsModule.save(app.getPath('userData'), settingsModule.merge(settings, partial));
    buildClient();                                // reconnect with the new config
    return settings;
  });
  ipcMain.handle('hub:regenCode', () => {
    settings = settingsModule.save(app.getPath('userData'),
      settingsModule.merge(settings, { pairingCode: settingsModule.generatePairingCode() }));
    buildClient();
    return settings.pairingCode;
  });
});

app.on('window-all-closed', (e) => { e.preventDefault(); /* stay alive in the menubar */ });
app.on('before-quit', () => { if (client) client.close(); });
```

- [ ] **Step 3: Add a tray icon asset**

Create a 16×16 transparent PNG at `menubar-hub/renderer/trayTemplate.png` (a simple filled dot or "CC" mark). If you don't have one yet, the code falls back to an empty image and uses the `● ◐ ○` title glyph, which is enough to ship. Generate a placeholder:

Run:
```bash
cd menubar-hub && mkdir -p renderer && \
printf '' > /dev/null # (drop a real 16x16 PNG here; title glyph works without it)
```

- [ ] **Step 4: Manual verify (renderer is built next task — just confirm it launches)**

Run: `cd menubar-hub && npm install && npm start`
Expected: a menubar glyph appears (`○`/`◐`); clicking it toggles an empty popover window (renderer content lands in Task C4). No dock icon. Quit via the menubar app menu or `Ctrl+C` in the terminal.

- [ ] **Step 5: Commit**

```bash
git add menubar-hub/main.js menubar-hub/preload.js
git commit -m "feat(menubar-hub): Electron tray + click-down popover + IPC wiring"
```

### Task C4: Popover renderer — status, pairing code, settings, styled log

**Files:**
- Create: `menubar-hub/renderer/index.html`
- Create: `menubar-hub/renderer/styles.css`
- Create: `menubar-hub/renderer/app.js`

- [ ] **Step 1: Write `menubar-hub/renderer/index.html`**

```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta http-equiv="Content-Security-Policy" content="default-src 'self'; style-src 'self';" />
  <link rel="stylesheet" href="styles.css" />
</head>
<body>
  <header>
    <span id="dot" class="dot offline"></span>
    <span id="status">offline</span>
  </header>

  <section class="pairing">
    <label>Pairing code</label>
    <div class="coderow">
      <code id="code">…</code>
      <button id="copy" title="Copy">Copy</button>
      <button id="regen" title="New code">↻</button>
    </div>
  </section>

  <section class="log">
    <div class="loghead">Activity</div>
    <ul id="feed"></ul>
  </section>

  <details class="settings">
    <summary>MA3 settings</summary>
    <label>Relay URL <input id="relayUrl" type="text" /></label>
    <label>MA3 host <input id="ma3Host" type="text" /></label>
    <label>MA3 port <input id="ma3Port" type="number" /></label>
    <label>OSC prefix <input id="ma3Prefix" type="text" /></label>
    <button id="save">Save</button>
  </details>

  <script src="app.js"></script>
</body>
</html>
```

- [ ] **Step 2: Write `menubar-hub/renderer/styles.css`**

```css
:root {
  --bg: #16181d; --surface: #1e2128; --text: #e6e8ec; --faint: #8b909a;
  --green: #3ad07a; --amber: #f2b134; --red: #e5564b; --accent: #6ea8fe;
  --send: #6ea8fe; --pull: #b18cff; --cmd: #3ad07a; --err: #e5564b;
}
* { box-sizing: border-box; }
body { margin: 0; font: 13px -apple-system, system-ui, sans-serif; color: var(--text);
  background: var(--bg); padding: 12px; user-select: none; }
header { display: flex; align-items: center; gap: 8px; font-weight: 600; margin-bottom: 12px; }
.dot { width: 10px; height: 10px; border-radius: 50%; }
.dot.online { background: var(--amber); }     /* relay up, no phone */
.dot.paired { background: var(--green); }      /* phone paired */
.dot.offline { background: var(--faint); }
.dot.error { background: var(--red); }

.pairing label, .loghead { color: var(--faint); font-size: 11px; text-transform: uppercase;
  letter-spacing: .04em; }
.coderow { display: flex; align-items: center; gap: 6px; margin-top: 4px; }
code#code { background: var(--surface); padding: 6px 10px; border-radius: 6px; flex: 1;
  font-size: 15px; letter-spacing: .08em; }
button { background: var(--surface); color: var(--text); border: none; border-radius: 6px;
  padding: 6px 10px; cursor: pointer; }
button:hover { background: #2a2e37; }

.log { margin-top: 14px; }
ul#feed { list-style: none; margin: 6px 0 0; padding: 0; max-height: 200px; overflow-y: auto; }
ul#feed li { display: flex; gap: 8px; padding: 4px 6px; border-radius: 5px; align-items: baseline; }
ul#feed li:nth-child(odd) { background: var(--surface); }
.ts { color: var(--faint); font-variant-numeric: tabular-nums; font-size: 11px; }
.kind { font-weight: 700; font-size: 11px; min-width: 42px; }
.kind.cmd { color: var(--cmd); } .kind.send { color: var(--send); }
.kind.pull { color: var(--pull); } .kind.error { color: var(--err); }
.summary { flex: 1; }

.settings { margin-top: 14px; }
.settings summary { color: var(--faint); cursor: pointer; }
.settings label { display: block; margin: 8px 0; color: var(--faint); }
.settings input { width: 100%; background: var(--surface); color: var(--text); border: none;
  border-radius: 6px; padding: 6px 8px; margin-top: 3px; }
```

- [ ] **Step 3: Write `menubar-hub/renderer/app.js`**

```js
'use strict';
const $ = (id) => document.getElementById(id);

function setStatus(relay, peer) {
  const dot = $('dot');
  dot.className = 'dot ' + (peer ? 'paired' : relay === 'online' ? 'online'
    : String(relay).startsWith('error') ? 'error' : 'offline');
  $('status').textContent = peer ? 'phone paired' : relay === 'online' ? 'waiting for phone' : relay;
}

function pad(n) { return String(n).padStart(2, '0'); }
function hhmmss(ms) { const d = new Date(ms); return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`; }

function addLog(entry) {
  const li = document.createElement('li');
  const kindLabel = { cmd: 'CMD', send: 'SEND', pull: 'PULL', error: 'ERR' }[entry.kind] || entry.kind.toUpperCase();
  li.innerHTML =
    `<span class="ts">${hhmmss(entry.at)}</span>` +
    `<span class="kind ${entry.kind}">${kindLabel}</span>` +
    `<span class="summary"></span>`;
  li.querySelector('.summary').textContent = entry.summary;   // textContent = no HTML injection
  const feed = $('feed');
  feed.prepend(li);
  while (feed.childElementCount > 200) feed.removeChild(feed.lastChild);
}

async function init() {
  const s = await window.hub.getSettings();
  $('relayUrl').value = s.relayUrl;
  $('ma3Host').value = s.ma3Host;
  $('ma3Port').value = s.ma3Port;
  $('ma3Prefix').value = s.ma3Prefix;
  $('code').textContent = s.pairingCode;

  const st = await window.hub.getState();
  setStatus(st.relay, st.peer);

  window.hub.onState((relay) => setStatus(relay, false));
  window.hub.onPeer((peer) => window.hub.getState().then((x) => setStatus(x.relay, peer)));
  window.hub.onLog(addLog);

  $('copy').onclick = () => navigator.clipboard.writeText($('code').textContent);
  $('regen').onclick = async () => { $('code').textContent = await window.hub.regenCode(); };
  $('save').onclick = async () => {
    const updated = await window.hub.setSettings({
      relayUrl: $('relayUrl').value.trim(),
      ma3Host: $('ma3Host').value.trim(),
      ma3Port: parseInt($('ma3Port').value, 10),
      ma3Prefix: $('ma3Prefix').value.trim(),
    });
    $('code').textContent = updated.pairingCode;
  };
}
init();
```

- [ ] **Step 4: Manual verify the popover**

Run: `cd menubar-hub && npm start`
Expected: clicking the menubar glyph shows the popover with the pairing code, an empty Activity feed, and the MA3 settings disclosure. With the relay deployed (Task B3), the status dot goes amber ("waiting for phone"); pairing a phone (Phase D) turns it green and rows appear in the feed as you tap GO+/PAUSE.

- [ ] **Step 5: Write `menubar-hub/README.md`** (run-from-source instructions)

````markdown
# Cuelist Compiler — Internet Hub (menubar)

A stripped-down, **hub-only** macOS menubar app. Use it when you just need the
laptop to act as a hub for the iPhone **over the internet** (cellular / different
WiFi). It pairs with the phone through the Fly relay and relays each command to
the desk over OSC/UDP. It reuses `hub/src/*` for compiling/OSC — so the whole
repo must be checked out. Separate from `desktop/` (the full authoring app).

## Run from source

```sh
cd menubar-hub
npm install
npm start
```

A glyph appears in the menubar (`○` offline · `◐` relay up, no phone · `●` phone
paired). Click it for status, the **pairing code**, a live activity log, and MA3
settings.

## Use it

1. Deploy/confirm the relay (`relay/README.md`) so `wss://cuelist-relay.fly.dev` is up.
2. Set MA3 **host/port/prefix** in the popover (e.g. `127.0.0.1` / `8000` / `gma3`
   for onPC on this Mac, or the desk's IP). On MA3: OSC input, **Echo Input = Yes**.
3. Copy the **pairing code** into the iPhone app (Settings → Relay).
4. The dot turns green when the phone pairs; GO+/GO-/PAUSE/Send/Pull from the
   phone now flow laptop → desk, and each shows in the Activity log.

## Test

```sh
cd menubar-hub && npm test
```
````

- [ ] **Step 6: Commit**

```bash
git add menubar-hub/renderer/ menubar-hub/README.md
git commit -m "feat(menubar-hub): popover UI — status, pairing code, styled activity log"
```

---

## PHASE D — iOS relay mode (`ios/`)

### Task D1: Message types for the relay handshake

**Files:**
- Modify: `ios/Sources/Kit/Hub/HubMessages.swift`
- Create: `ios/Tests/KitTests/RelayModeTests.swift`

- [ ] **Step 1: Write the failing test** — `ios/Tests/KitTests/RelayModeTests.swift`

```swift
import XCTest
@testable import CuelistCompilerKit

final class RelayModeTests: XCTestCase {
    func testJoinFrameEncodesRoleAndRoom() throws {
        let json = try OutgoingMessage.join(room: "CODE1234", role: "phone").jsonString()
        XCTAssertTrue(json.contains("\"type\":\"join\""))
        XCTAssertTrue(json.contains("\"room\":\"CODE1234\""))
        XCTAssertTrue(json.contains("\"role\":\"phone\""))
    }

    func testDecodePeerConnected() throws {
        let msg = try IncomingMessage.decode("{\"type\":\"peer\",\"connected\":true}")
        XCTAssertEqual(msg, .peer(connected: true))
    }

    func testDecodeJoined() throws {
        let msg = try IncomingMessage.decode("{\"type\":\"joined\"}")
        XCTAssertEqual(msg, .joined)
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project and run the test to verify it fails**

Run:
```bash
cd ios && xcodegen generate && \
xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:CuelistCompilerKitTests/RelayModeTests 2>&1 | tail -20
```
Expected: FAIL — `OutgoingMessage.join` and `.peer`/`.joined` cases don't exist.

- [ ] **Step 3: Extend `ios/Sources/Kit/Hub/HubMessages.swift`**

Add the `join` case to `OutgoingMessage` (place beside `cmd`):

```swift
    case join(room: String, role: String)
```

Add its payload struct (beside `Cmd`):

```swift
    private struct Join: Encodable { let type = "join"; let room: String; let role: String }
```

Add its encode arm (in the `switch self` inside `jsonData()`):

```swift
        case let .join(room, role):
            return try enc.encode(Join(room: room, role: role))
```

Add the two relay-control cases to `IncomingMessage`:

```swift
    case joined                                      // relay: this side joined a room
    case peer(connected: Bool)                       // relay: the other side connected/dropped
```

Extend the `Envelope` with the `connected` field:

```swift
        let connected: Bool?
```

Add the decode arms (in `switch e.type`, before `default`):

```swift
        case "joined":     return .joined
        case "peer":       return .peer(connected: e.connected ?? false)
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd ios && xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:CuelistCompilerKitTests/RelayModeTests 2>&1 | tail -20
```
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Hub/HubMessages.swift ios/Tests/KitTests/RelayModeTests.swift ios/project.yml
git commit -m "feat(ios): relay join/peer message types"
```

### Task D2: HubClient connection mode (direct | relay) + join handshake

**Files:**
- Modify: `ios/Sources/Kit/Hub/HubClient.swift`
- Modify: `ios/Tests/KitTests/RelayModeTests.swift`

- [ ] **Step 1: Add failing tests** — append to `ios/Tests/KitTests/RelayModeTests.swift`

```swift
@MainActor
final class HubClientRelayTests: XCTestCase {
    // A fake connection that records sends and lets the test drive events.
    final class FakeConn: HubConnection {
        var sent: [String] = []
        var onEvent: ((HubConnectionEvent) -> Void)?
        func connect(onEvent: @escaping (HubConnectionEvent) -> Void) { self.onEvent = onEvent }
        func send(_ text: String) { sent.append(text) }
        func close() {}
    }

    func makeClient(_ conn: FakeConn) -> HubClient {
        let d = UserDefaults(suiteName: "relay.test.\(UUID().uuidString)")!
        let c = HubClient(defaults: d, makeConnection: { _ in conn })
        c.mode = .relay
        c.relayURL = "wss://cuelist-relay.fly.dev"
        c.pairingCode = "CODE1234"
        return c
    }

    func testRelayConnectSendsJoinOnOpen() {
        let conn = FakeConn()
        let c = makeClient(conn)
        c.connect()
        conn.onEvent?(.opened)
        XCTAssertTrue(conn.sent.contains { $0.contains("\"type\":\"join\"") && $0.contains("CODE1234") })
    }

    func testStaysConnectingUntilPeerThenOnline() {
        let conn = FakeConn()
        let c = makeClient(conn)
        c.connect()
        conn.onEvent?(.opened)
        XCTAssertEqual(c.state, .connecting)                       // joined, but no phone-side peer yet
        conn.onEvent?(.text("{\"type\":\"peer\",\"connected\":true}"))
        XCTAssertEqual(c.state, .online)
        conn.onEvent?(.text("{\"type\":\"peer\",\"connected\":false}"))
        XCTAssertEqual(c.state, .connecting)
    }

    func testRelayURLBuiltFromRelayURLNotHostPort() {
        let conn = FakeConn()
        let c = makeClient(conn)
        XCTAssertEqual(c.url?.absoluteString, "wss://cuelist-relay.fly.dev")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
cd ios && xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:CuelistCompilerKitTests/HubClientRelayTests 2>&1 | tail -25
```
Expected: FAIL — `mode`, `relayURL`, `pairingCode`, and `.relay` don't exist.

- [ ] **Step 3: Edit `ios/Sources/Kit/Hub/HubClient.swift`**

Add the mode enum (above the class):

```swift
public enum HubMode: String, Sendable { case direct, relay }
```

Add stored properties + keys (beside `host`/`port`):

```swift
    public var mode: HubMode { didSet { defaults.set(mode.rawValue, forKey: Keys.mode) } }
    public var relayURL: String { didSet { defaults.set(relayURL, forKey: Keys.relayURL) } }
    public var pairingCode: String { didSet { defaults.set(pairingCode, forKey: Keys.pairingCode) } }
```

Extend `Keys`:

```swift
    private enum Keys {
        static let host = "hubHost"; static let port = "hubPort"
        static let mode = "hubMode"; static let relayURL = "hubRelayURL"; static let pairingCode = "hubPairingCode"
    }
```

Initialize them in `init` (after the existing host/port lines):

```swift
        self.mode = HubMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .direct
        self.relayURL = defaults.string(forKey: Keys.relayURL) ?? ""
        self.pairingCode = defaults.string(forKey: Keys.pairingCode) ?? ""
```

Replace the `url` computed property to branch on mode:

```swift
    public var url: URL? {
        switch mode {
        case .direct: return host.isEmpty ? nil : URL(string: "ws://\(host):\(port)")
        case .relay:  return relayURL.isEmpty ? nil : URL(string: relayURL)
        }
    }
```

Replace `connect()` so relay mode sends the join frame on open and gates `.online` on the peer:

```swift
    public func connect() {
        guard let url else {
            state = .error(mode == .relay ? "set relay URL + pairing code" : "set hub host first")
            return
        }
        state = .connecting
        connection?.close()
        let conn = makeConnection(url)
        connection = conn
        conn.connect { [weak self] event in
            guard let self else { return }
            switch event {
            case .opened:
                switch self.mode {
                case .direct:
                    self.state = .online
                case .relay:
                    // Join the room first; stay .connecting until the laptop (peer) is present.
                    if let join = try? OutgoingMessage.join(room: self.pairingCode, role: "phone").jsonString() {
                        conn.send(join)
                    }
                }
            case let .text(text):
                self.handle(text)
            case let .closed(reason):
                self.state = reason.map(ConnectionState.error) ?? .offline
            }
        }
    }
```

Extend `handle(_:)` to react to the relay control frames (add cases before `.other`):

```swift
        case .joined:
            break                                  // waiting for a peer; no state change yet
        case let .peer(connected):
            state = connected ? .online : .connecting
```

- [ ] **Step 4: Run to verify it passes**

Run:
```bash
cd ios && xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:CuelistCompilerKitTests/HubClientRelayTests 2>&1 | tail -25
```
Expected: PASS — 3 tests. Also re-run the whole Kit suite to confirm no regression:
`xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5` → all green.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Hub/HubClient.swift ios/Tests/KitTests/RelayModeTests.swift
git commit -m "feat(ios): HubClient direct|relay mode with join handshake + peer gating"
```

### Task D3: Settings UI — mode toggle + relay fields

**Files:**
- Modify: `ios/Sources/App/SettingsView.swift`

- [ ] **Step 1: Replace the `Hub` section in `SettingsView.swift`**

Swap the existing `Section("Hub") { … }` for a mode-aware version:

```swift
                Section("Connection") {
                    Picker("Mode", selection: $hub.mode) {
                        Text("Direct (same WiFi)").tag(HubMode.direct)
                        Text("Relay (internet)").tag(HubMode.relay)
                    }
                    .pickerStyle(.segmented)

                    if hub.mode == .direct {
                        TextField("Host (laptop/Pi LAN IP)", text: $hub.host)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        TextField("Port", value: $hub.port, format: .number)
                            .keyboardType(.numberPad)
                    } else {
                        TextField("Relay URL", text: $hub.relayURL)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        TextField("Pairing code (from the laptop)", text: $hub.pairingCode)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    Button("Connect") { hub.connect() }
                }
```

- [ ] **Step 2: Pre-fill the relay URL default so the field isn't empty on first use**

In `SettingsView`'s `.onAppear`, add (after the key loads):

```swift
                if hub.relayURL.isEmpty { hub.relayURL = "wss://cuelist-relay.fly.dev" }
```

- [ ] **Step 3: Build the app to confirm it compiles**

Run:
```bash
cd ios && xcodegen generate && \
xcodebuild build -scheme CuelistCompiler \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App/SettingsView.swift ios/project.yml
git commit -m "feat(ios): settings UI — Direct/Relay mode toggle + relay fields"
```

---

## PHASE E — End-to-end smoke (manual, acceptance bar)

### Task E1: Full off-WiFi smoke test

No code — this is the acceptance gate. Record the result.

- [ ] **Step 1: Confirm the relay is live**

Run: `curl -fsS https://cuelist-relay.fly.dev/healthz`
Expected: `ok`.

- [ ] **Step 2: Start the laptop hub + point it at MA3**

Run: `cd menubar-hub && npm start`
- Open the popover, set MA3 host/port/prefix (onPC on this Mac → `127.0.0.1` / `8000` / `gma3`; real desk → its IP). Note the **pairing code**.
- On MA3: OSC input enabled, port `8000`, prefix `gma3`, **Echo Input = Yes**.
- The popover dot should be **amber** ("waiting for phone").

- [ ] **Step 3: Pair the phone over cellular (true off-WiFi)**

- On the iPhone: **turn WiFi off** (force cellular), open the app → Settings → Connection → **Relay**, enter the relay URL + pairing code → **Connect**.
- The laptop popover dot turns **green** ("phone paired"); the phone shows online.

- [ ] **Step 4: Drive the desk and verify the log**

From the phone, exercise each path and confirm both the desk reacts and the popover log shows a row:
- Live tab: **GO+**, **GO-**, **PAUSE** → `CMD Go+` / `Go-` / `Pause` rows.
- Send tab: **Send all** → `SEND all → N lines` row; cues land in the desk.
- Pull → `PULL N sequences` row; the list returns to the phone.

- [ ] **Step 5: Record the outcome**

Update `docs/superpowers/specs/2026-06-06-internet-hub-design.md` (or a new `RESULTS` note) with the date, MA3 target (onPC/desk), and which paths passed. Commit:

```bash
git add docs/superpowers/
git commit -m "docs: internet hub end-to-end smoke results"
```

---

## Notes for the executor

- **Dependency order is strict across phases:** A (handle.js) before C2 (relay-client imports it); B deployed before D3/E can pair; C and D can otherwise proceed in parallel once A and B exist.
- **Run from source** is the shipping bar for `menubar-hub/` (no signed installer in v1), matching where `desktop/` is today.
- **`xcodegen generate` before every `xcodebuild`** (iOS). Test sim: iPhone 17 Pro.
- **No iOS ATS change needed:** `wss://` to Fly uses a valid public TLS cert, satisfied by default ATS; the existing `NSAllowsLocalNetworking` still covers direct-mode `ws://`.
- **Relay-only v1:** hybrid LAN-direct-with-relay-fallback is explicitly deferred (spec §Open).
