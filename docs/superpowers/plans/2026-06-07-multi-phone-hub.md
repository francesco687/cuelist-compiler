# Multiple iPhones → one Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let multiple iPhones drive one grandMA3 desk through a single Saetta Hub over the Fly relay, with per-operator attribution, a live roster, and frictionless persistent pairing.

**Architecture:** The relay routes each phone's request/reply pair via a per-connection id (`cid`) envelope so replies reach only the originating phone; app frames stay opaque inside the envelope. Phones identify by device name, the hub shows who's connected and who sent what, phones auto-reconnect with backoff, and the pairing code is editable + persisted on first run. `compile-send` is serialized on the hub so concurrent show-pushes don't interleave OSC.

**Tech Stack:** Node (`relay/`, `menubar-hub/`, `hub/`) tested with `node --test`; Swift `SaettaKit` tested with XCTest; Electron renderer (vanilla JS).

**Spec:** `docs/superpowers/specs/2026-06-07-multi-phone-hub-design.md`

**Test commands:**
- Relay: `cd relay && npm test`
- Menubar hub: `cd menubar-hub && npm test`
- Hub core: `cd hub && npm test`
- Kit: `cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- App build: `cd ios && xcodegen generate && xcodebuild build -scheme Saetta -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

---

### Task 1: Relay rooms — multi-phone model, roster, routing

Rewrite the pure `Rooms` class: one hub + many phones per room, cid assignment, roster broadcast, envelope routing, and room-full cap. This is a self-contained rewrite of a small pure module (no network).

**Files:**
- Modify: `relay/src/rooms.js`
- Test: `relay/test/rooms.test.js`

- [ ] **Step 1: Replace the room-model tests**

Replace the entire body of `relay/test/rooms.test.js` (keep the `'use strict'`, requires, and `fakeSocket` helper at top) with these tests:

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const { Rooms } = require('../src/rooms');

// Fake socket: records every string passed to .send().
function fakeSocket() { const out = []; return { out, send: (s) => out.push(JSON.parse(s)) }; }

test('phone join assigns a cid and tells the hub + phones a roster', () => {
  const rooms = new Rooms();
  const hub = fakeSocket();
  assert.deepStrictEqual(rooms.join(hub, 'roomcode1', 'hub'), { ok: true });
  assert.deepStrictEqual(hub.out, [{ type: 'joined' }, { type: 'roster', phones: [] }]);

  const phone = fakeSocket();
  hub.out.length = 0;
  assert.deepStrictEqual(rooms.join(phone, 'roomcode1', 'phone', "Matteo's iPhone"), { ok: true });
  // phone gets joined-with-cid then a roster carrying hub presence
  assert.deepStrictEqual(phone.out[0], { type: 'joined', cid: 'p1' });
  assert.deepStrictEqual(phone.out[1], { type: 'roster', hub: true, phones: [{ cid: 'p1', name: "Matteo's iPhone" }] });
  // hub gets the phones-only roster
  assert.deepStrictEqual(hub.out, [{ type: 'roster', phones: [{ cid: 'p1', name: "Matteo's iPhone" }] }]);
});

test('two phones both appear in the roster broadcast', () => {
  const rooms = new Rooms();
  const hub = fakeSocket();
  rooms.join(hub, 'roomcode1', 'hub');
  rooms.join(fakeSocket(), 'roomcode1', 'phone', 'A');
  hub.out.length = 0;
  rooms.join(fakeSocket(), 'roomcode1', 'phone', 'B');
  assert.deepStrictEqual(hub.out, [{ type: 'roster', phones: [{ cid: 'p1', name: 'A' }, { cid: 'p2', name: 'B' }] }]);
});

test('blank/missing name defaults to iPhone', () => {
  const rooms = new Rooms();
  const hub = fakeSocket();
  rooms.join(hub, 'roomcode1', 'hub');
  hub.out.length = 0;
  rooms.join(fakeSocket(), 'roomcode1', 'phone');
  assert.deepStrictEqual(hub.out[0].phones, [{ cid: 'p1', name: 'iPhone' }]);
});

test('phone frame is wrapped from-phone toward the hub only', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), phone = fakeSocket();
  rooms.join(hub, 'roomcode1', 'hub');
  rooms.join(phone, 'roomcode1', 'phone', 'Matteo');
  hub.out.length = 0; phone.out.length = 0;
  rooms.forward(phone, JSON.stringify({ type: 'cmd', line: 'Go+' }));
  assert.deepStrictEqual(hub.out, [{ type: 'from-phone', cid: 'p1', name: 'Matteo', frame: '{"type":"cmd","line":"Go+"}' }]);
  assert.deepStrictEqual(phone.out, []);
});

test('hub to-phone reply is unwrapped to the one targeted phone', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), a = fakeSocket(), b = fakeSocket();
  rooms.join(hub, 'roomcode1', 'hub');
  rooms.join(a, 'roomcode1', 'phone', 'A');   // p1
  rooms.join(b, 'roomcode1', 'phone', 'B');   // p2
  a.out.length = 0; b.out.length = 0;
  rooms.forward(hub, JSON.stringify({ type: 'to-phone', cid: 'p2', frame: '{"type":"pong"}' }));
  assert.deepStrictEqual(a.out, []);
  assert.deepStrictEqual(b.out, [{ type: 'pong' }]);
});

test('legacy un-enveloped hub frame is broadcast to all phones', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), a = fakeSocket(), b = fakeSocket();
  rooms.join(hub, 'roomcode1', 'hub');
  rooms.join(a, 'roomcode1', 'phone', 'A');
  rooms.join(b, 'roomcode1', 'phone', 'B');
  a.out.length = 0; b.out.length = 0;
  rooms.forward(hub, JSON.stringify({ type: 'sent', line: 'Go+' }));
  assert.deepStrictEqual(a.out, [{ type: 'sent', line: 'Go+' }]);
  assert.deepStrictEqual(b.out, [{ type: 'sent', line: 'Go+' }]);
});

test('room full past maxPhones is rejected', () => {
  const rooms = new Rooms({ maxPhones: 2 });
  rooms.join(fakeSocket(), 'roomcode1', 'hub');
  rooms.join(fakeSocket(), 'roomcode1', 'phone', 'A');
  rooms.join(fakeSocket(), 'roomcode1', 'phone', 'B');
  assert.deepStrictEqual(rooms.join(fakeSocket(), 'roomcode1', 'phone', 'C'), { ok: false, error: 'room full' });
});

test('second hub is still rejected', () => {
  const rooms = new Rooms();
  rooms.join(fakeSocket(), 'roomcode1', 'hub');
  assert.deepStrictEqual(rooms.join(fakeSocket(), 'roomcode1', 'hub'), { ok: false, error: 'role taken' });
});

test('leaving phone is dropped and roster rebroadcast', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), a = fakeSocket();
  rooms.join(hub, 'roomcode1', 'hub');
  rooms.join(a, 'roomcode1', 'phone', 'A');
  hub.out.length = 0;
  rooms.leave(a);
  assert.deepStrictEqual(hub.out, [{ type: 'roster', phones: [] }]);
});

test('room is deleted only when hub and all phones are gone', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), a = fakeSocket();
  rooms.join(hub, 'roomcode1', 'hub');
  rooms.join(a, 'roomcode1', 'phone', 'A');
  rooms.leave(a);
  assert.strictEqual(rooms.rooms.has('roomcode1'), true);
  rooms.leave(hub);
  assert.strictEqual(rooms.rooms.has('roomcode1'), false);
});

test('short code is rejected', () => {
  const rooms = new Rooms();
  assert.deepStrictEqual(rooms.join(fakeSocket(), 'abc', 'hub'), { ok: false, error: 'bad room' });
});
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd relay && npm test`
Expected: FAIL (old `Rooms` has no `phones`/cid/roster behavior).

- [ ] **Step 3: Rewrite `relay/src/rooms.js`**

Replace the whole file with:

```js
'use strict';
// Pure pairing logic — no network. A "socket" is any object with .send(string).
// One hub + many phones share a room keyed by the pairing code. Phone frames are
// wrapped {from-phone, cid, name, frame} toward the hub; the hub replies with
// {to-phone, cid, frame} and the relay unwraps + routes the inner frame to that
// one phone. An un-enveloped hub frame is broadcast (legacy single-phone hubs).

const MIN_CODE_LEN = 6;

class Rooms {
  constructor({ maxRooms = 200, maxPhones = 8 } = {}) {
    this.maxRooms = maxRooms;
    this.maxPhones = maxPhones;
    this.rooms = new Map();   // code -> { hub: socket|null, phones: Map<cid,{socket,name}> }
    this._cid = 0;
  }

  _roster(room) {
    return [...room.phones.entries()].map(([cid, p]) => ({ cid, name: p.name }));
  }

  _broadcastRoster(room) {
    const phones = this._roster(room);
    const hubPresent = !!room.hub;
    if (room.hub) room.hub.send(JSON.stringify({ type: 'roster', phones }));
    for (const { socket } of room.phones.values()) {
      socket.send(JSON.stringify({ type: 'roster', hub: hubPresent, phones }));
    }
  }

  join(socket, code, role, name) {
    if (role !== 'hub' && role !== 'phone') return { ok: false, error: 'bad role' };
    if (typeof code !== 'string' || code.length < MIN_CODE_LEN) return { ok: false, error: 'bad room' };

    let room = this.rooms.get(code);
    if (!room) {
      if (this.rooms.size >= this.maxRooms) return { ok: false, error: 'relay full' };
      room = { hub: null, phones: new Map() };
      this.rooms.set(code, room);
    }

    if (role === 'hub') {
      if (room.hub) return { ok: false, error: 'role taken' };
      room.hub = socket;
      socket._room = code; socket._role = 'hub';
      socket.send(JSON.stringify({ type: 'joined' }));
      this._broadcastRoster(room);
      return { ok: true };
    }

    if (room.phones.size >= this.maxPhones) return { ok: false, error: 'room full' };
    const cid = 'p' + (++this._cid);
    const clean = (typeof name === 'string' && name.trim()) ? name : 'iPhone';
    room.phones.set(cid, { socket, name: clean });
    socket._room = code; socket._role = 'phone'; socket._cid = cid;
    socket.send(JSON.stringify({ type: 'joined', cid }));
    this._broadcastRoster(room);
    return { ok: true };
  }

  forward(socket, rawText) {
    const code = socket._room;
    if (!code) return;
    const room = this.rooms.get(code);
    if (!room) return;

    if (socket._role === 'phone') {
      if (!room.hub) return;
      const entry = room.phones.get(socket._cid);
      room.hub.send(JSON.stringify({ type: 'from-phone', cid: socket._cid, name: entry && entry.name, frame: rawText }));
      return;
    }

    // hub -> phone(s)
    let msg;
    try { msg = JSON.parse(rawText); } catch { msg = null; }
    if (msg && msg.type === 'to-phone') {
      const target = room.phones.get(msg.cid);
      if (target && typeof msg.frame === 'string') target.socket.send(msg.frame);
      return;
    }
    for (const { socket: ps } of room.phones.values()) ps.send(rawText);   // legacy broadcast
  }

  leave(socket) {
    const code = socket._room;
    if (!code) return;
    const room = this.rooms.get(code);
    if (!room) return;
    if (socket._role === 'hub' && room.hub === socket) room.hub = null;
    if (socket._role === 'phone') room.phones.delete(socket._cid);
    if (!room.hub && room.phones.size === 0) { this.rooms.delete(code); return; }
    this._broadcastRoster(room);
  }
}

module.exports = { Rooms, MIN_CODE_LEN };
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd relay && npm test`
Expected: PASS (rooms.test.js green; server.test.js may still fail — fixed in Task 2).

- [ ] **Step 5: Commit**

```bash
git add relay/src/rooms.js relay/test/rooms.test.js
git commit -m "feat(relay): multi-phone rooms with cid routing + roster"
```

---

### Task 2: Relay server — thread the join name + multi-phone integration test

`server.js` already forwards post-join frames via `rooms.forward`. The only code change is passing `msg.name` into `rooms.join`. Update the integration tests for the multi-phone model.

**Files:**
- Modify: `relay/src/server.js:38` (the `rooms.join` call)
- Test: `relay/test/server.test.js`

- [ ] **Step 1: Update the end-to-end test to the multi-phone frames + add a two-phone test**

The file already provides `open(url)` (returns a connected `ws`) and `reader(ws)` (returns a `next()` that resolves frames in arrival order), `startRelay({ port: 0 })`, `relay.server.address().port`, and `relay.close()`. Replace the existing `'two clients with the same code exchange a forwarded frame end to end'` test body with the new frame shapes, and append the two-phone test:

```js
test('a phone bridges to one hub end to end (cid envelope + roster)', async () => {
  const relay = startRelay({ port: 0 });
  const port = relay.server.address().port;
  const url = `ws://127.0.0.1:${port}`;

  const hub = await open(url);
  const hubNext = reader(hub);
  hub.send(JSON.stringify({ type: 'join', room: 'ENDTOEND1', role: 'hub' }));
  assert.deepStrictEqual(await hubNext(), { type: 'joined' });
  assert.deepStrictEqual(await hubNext(), { type: 'roster', phones: [] });

  const phone = await open(url);
  const phoneNext = reader(phone);
  phone.send(JSON.stringify({ type: 'join', room: 'ENDTOEND1', role: 'phone', name: 'Matteo' }));
  assert.deepStrictEqual(await phoneNext(), { type: 'joined', cid: 'p1' });
  assert.deepStrictEqual(await phoneNext(), { type: 'roster', hub: true, phones: [{ cid: 'p1', name: 'Matteo' }] });
  assert.deepStrictEqual(await hubNext(), { type: 'roster', phones: [{ cid: 'p1', name: 'Matteo' }] });

  phone.send(JSON.stringify({ type: 'cmd', line: 'Go+' }));
  assert.deepStrictEqual(await hubNext(),
    { type: 'from-phone', cid: 'p1', name: 'Matteo', frame: '{"type":"cmd","line":"Go+"}' });

  hub.send(JSON.stringify({ type: 'to-phone', cid: 'p1', frame: JSON.stringify({ type: 'sent', line: 'Go+' }) }));
  assert.deepStrictEqual(await phoneNext(), { type: 'sent', line: 'Go+' });

  hub.close(); phone.close();
  await relay.close();
});

test('a hub reply routes to only the addressed phone', async () => {
  const relay = startRelay({ port: 0 });
  const port = relay.server.address().port;
  const url = `ws://127.0.0.1:${port}`;

  const hub = await open(url);
  const hubNext = reader(hub);
  hub.send(JSON.stringify({ type: 'join', room: 'FANOUT01', role: 'hub' }));
  await hubNext(); await hubNext();                 // joined + empty roster

  const a = await open(url); const aNext = reader(a);
  a.send(JSON.stringify({ type: 'join', room: 'FANOUT01', role: 'phone', name: 'A' }));
  assert.deepStrictEqual((await aNext()).cid, 'p1');
  await aNext();                                     // roster

  const b = await open(url); const bNext = reader(b);
  b.send(JSON.stringify({ type: 'join', room: 'FANOUT01', role: 'phone', name: 'B' }));
  assert.deepStrictEqual((await bNext()).cid, 'p2');
  await bNext(); await aNext();                      // both phones get the updated roster
  await hubNext();                                   // hub gets the updated roster

  // Reply addressed to p2 only — p2 receives it, p1 receives nothing more.
  hub.send(JSON.stringify({ type: 'to-phone', cid: 'p2', frame: JSON.stringify({ type: 'pong' }) }));
  assert.deepStrictEqual(await bNext(), { type: 'pong' });

  let aGotExtra = false;
  const race = aNext().then(() => { aGotExtra = true; });
  await Promise.race([race, new Promise((r) => setTimeout(r, 50))]);
  assert.strictEqual(aGotExtra, false);

  hub.close(); a.close(); b.close();
  await relay.close();
});
```

> The `cid` values are deterministic per fresh relay process (`p1`, `p2`, …) because each `startRelay` builds a new `Rooms` with its own counter.

- [ ] **Step 2: Run and confirm failure**

Run: `cd relay && npm test`
Expected: FAIL (server still calls `rooms.join` without `name`; old `peer` assertions fail).

- [ ] **Step 3: Pass the join name through**

In `relay/src/server.js`, change the join call:

```js
const res = rooms.join(ws, msg.room, msg.role, msg.name);
```

- [ ] **Step 4: Run and confirm pass**

Run: `cd relay && npm test`
Expected: PASS (all relay tests green).

- [ ] **Step 5: Commit**

```bash
git add relay/src/server.js relay/test/server.test.js
git commit -m "feat(relay): thread join name; multi-phone server test"
```

---

### Task 3: Menubar hub relay-client — from-phone routing, attribution, roster

Handle the `from-phone` envelope, route replies back as `to-phone`, attach the operator name to log entries, and expose a roster hook. Replace `onPeer` with `onRoster`.

**Files:**
- Modify: `menubar-hub/src/relay-client.js`
- Test: `menubar-hub/test/relay-client.test.js`

- [ ] **Step 1: Update/extend the relay-client tests**

In `menubar-hub/test/relay-client.test.js`, replace the existing `'peer frame drives onPeer; ...'` test with these (keep the file's `FakeSocket`, `fakeDeps`, `config`):

```js
test('from-phone frame reaches OSC and replies via a to-phone envelope; log carries the name', async () => {
  const sock = new FakeSocket();
  const { osc, core } = fakeDeps();
  const logs = [];
  const c = new RelayHubClient(config, { onLog: (e) => logs.push(e) }, { makeSocket: () => sock, core });
  c.connect();
  sock.emit('open');

  sock.emit('message', Buffer.from(JSON.stringify({
    type: 'from-phone', cid: 'p1', name: 'Matteo', frame: JSON.stringify({ type: 'cmd', line: 'Go+' }),
  })));
  await new Promise((r) => setTimeout(r, 0));

  assert.deepStrictEqual(osc, ['Go+']);
  const reply = sock.sent.find((m) => m.type === 'to-phone');
  assert.ok(reply, 'expected a to-phone reply');
  assert.strictEqual(reply.cid, 'p1');
  assert.deepStrictEqual(JSON.parse(reply.frame), { type: 'sent', line: 'Go+' });
  assert.ok(logs.some((e) => e.kind === 'cmd' && e.name === 'Matteo'));
});

test('roster frame drives onRoster', () => {
  const sock = new FakeSocket();
  const { core } = fakeDeps();
  const rosters = [];
  const c = new RelayHubClient(config, { onRoster: (p) => rosters.push(p) }, { makeSocket: () => sock, core });
  c.connect();
  sock.emit('open');
  sock.emit('message', Buffer.from(JSON.stringify({ type: 'roster', phones: [{ cid: 'p1', name: 'Matteo' }] })));
  assert.deepStrictEqual(rosters, [[{ cid: 'p1', name: 'Matteo' }]]);
});
```

- [ ] **Step 2: Run and confirm failure**

Run: `cd menubar-hub && npm test`
Expected: FAIL (no `from-phone`/`roster` handling).

- [ ] **Step 3: Update `relay-client.js`**

Change the control-types set and `_onMessage`, replace `_peer` with `_roster`, and update the `close` handler:

```js
const CONTROL_TYPES = new Set(['joined', 'roster', 'join-error']);
```

```js
  _state(s) { this.hooks.onState && this.hooks.onState(s); }
  _roster(phones) { this.hooks.onRoster && this.hooks.onRoster(phones); }
  _log(entry) { this.hooks.onLog && this.hooks.onLog(entry); }
```

In `connect()`'s `ws.on('close', ...)` replace `this._peer(false);` with `this._roster([]);`.

Replace `_onMessage` with:

```js
  async _onMessage(text) {
    let msg;
    try { msg = JSON.parse(text); } catch { return; }

    if (CONTROL_TYPES.has(msg.type)) {
      if (msg.type === 'roster') this._roster(msg.phones || []);
      if (msg.type === 'join-error') this._state(`error: ${msg.message}`);
      return;
    }

    if (msg.type === 'from-phone') {
      let frame;
      try { frame = JSON.parse(msg.frame); } catch { return; }
      const cid = msg.cid;
      const reply = (obj) => {
        try { this.ws.send(JSON.stringify({ type: 'to-phone', cid, frame: JSON.stringify(obj) })); } catch {}
      };
      const out = await this.core.handleMessage(this.ctx, frame, reply);
      if (out && out.kind && out.kind !== 'ping') this._log({ ...out, name: msg.name, at: Date.now() });
      return;
    }
  }
```

- [ ] **Step 4: Run and confirm pass**

Run: `cd menubar-hub && npm test`
Expected: PASS (relay-client tests green; settings tests still green).

- [ ] **Step 5: Commit**

```bash
git add menubar-hub/src/relay-client.js menubar-hub/test/relay-client.test.js
git commit -m "feat(hub): relay-client from-phone routing + roster + log attribution"
```

---

### Task 4: Hub core — serialize compile-send (async mutex)

Add a tiny promise-chain mutex and wrap `compile-send` so two concurrent whole-show pushes can't interleave OSC lines. Single `cmd` frames stay unlocked (free-for-all).

**Files:**
- Create: `hub/src/serialize.js`
- Create: `hub/test/serialize.test.js`
- Modify: `hub/src/handle.js`

- [ ] **Step 1: Write the mutex test**

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const { createMutex } = require('../src/serialize');

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

test('createMutex runs tasks one at a time in call order', async () => {
  const run = createMutex();
  const order = [];
  const a = run(async () => { await delay(20); order.push('a'); });
  const b = run(async () => { await delay(1); order.push('b'); });
  await Promise.all([a, b]);
  assert.deepStrictEqual(order, ['a', 'b']);   // b waited for a despite being faster
});

test('a failing task does not break the chain', async () => {
  const run = createMutex();
  const order = [];
  const a = run(async () => { throw new Error('boom'); });
  await assert.rejects(a, /boom/);
  await run(async () => { order.push('b'); });
  assert.deepStrictEqual(order, ['b']);
});
```

- [ ] **Step 2: Run and confirm failure**

Run: `cd hub && npm test`
Expected: FAIL (`serialize` module missing).

- [ ] **Step 3: Create `hub/src/serialize.js`**

```js
'use strict';
// Tiny async mutex: chains tasks so they run one-at-a-time in call order.
// Each call returns the task's own promise; the chain survives task failures.
function createMutex() {
  let tail = Promise.resolve();
  return function run(task) {
    const result = tail.then(() => task());
    tail = result.then(() => {}, () => {});
    return result;
  };
}
module.exports = { createMutex };
```

- [ ] **Step 4: Wire it into `hub/src/handle.js`**

At the top, add the import beside the others:

```js
const { createMutex } = require('./serialize');
```

In `createContext`, add the lock to the returned context:

```js
  return { api, sender, config, lock: createMutex() };
```

Wrap the `compile-send` branch body. Change:

```js
  if (msg.type === 'compile-send') {
    let lines;
```

to:

```js
  if (msg.type === 'compile-send') {
    return ctx.lock(async () => {
      let lines;
```

and close the lambda at the end of that branch — the branch currently ends with its final `catch (e) { ... return { kind: 'error', ... }; }`. Add the closing `});` right after that branch's closing brace, before the `if (msg.type === 'cmd' ...)` line. The wrapped body keeps using `api`, `sender`, `config` (already destructured above) and the passed-in `reply`.

- [ ] **Step 5: Run and confirm pass**

Run: `cd hub && npm test`
Expected: PASS (serialize tests green; existing hub tests still green).

- [ ] **Step 6: Commit**

```bash
git add hub/src/serialize.js hub/test/serialize.test.js hub/src/handle.js
git commit -m "feat(hub): serialize compile-send so concurrent pushes don't interleave"
```

---

### Task 5: Settings — editable custom code + first-run persistence

Relax validation to accept memorable custom codes (`[a-z0-9]{6,}`) and add `loadOrInit` that writes defaults on first run so the generated code never silently regenerates.

**Files:**
- Modify: `menubar-hub/src/settings.js`
- Test: `menubar-hub/test/settings.test.js`

- [ ] **Step 1: Add tests**

Append to `menubar-hub/test/settings.test.js` (extend the existing top `require` to also import `validate`, `load`, `save`, `loadOrInit`, `filePath`; add `fs`/`os`/`path` requires):

```js
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { load, save, loadOrInit, filePath } = require('../src/settings');

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
```

- [ ] **Step 2: Run and confirm failure**

Run: `cd menubar-hub && npm test`
Expected: FAIL (`loadOrInit` missing; custom-code validation tests fail).

- [ ] **Step 3: Update `settings.js`**

Replace the pairingCode line in `validate`:

```js
  if (typeof s.pairingCode !== 'string' || !/^[a-z0-9]{6,}$/.test(s.pairingCode)) throw new Error('invalid pairingCode');
```

Add `loadOrInit` after `save` and export it:

```js
function loadOrInit(userDataDir) {
  if (!fs.existsSync(filePath(userDataDir))) return save(userDataDir, defaults());
  return load(userDataDir);
}
```

```js
module.exports = { defaults, merge, validate, load, save, loadOrInit, filePath, generatePairingCode };
```

- [ ] **Step 4: Run and confirm pass**

Run: `cd menubar-hub && npm test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add menubar-hub/src/settings.js menubar-hub/test/settings.test.js
git commit -m "feat(hub): editable custom pairing code + first-run persistence"
```

---

### Task 6: Menubar main + renderer — persist on launch, editable code, roster, attribution

Wire `loadOrInit` on launch, replace the peer hook with roster, make the code an editable field, render the roster, and show operator names in the log.

**Files:**
- Modify: `menubar-hub/main.js`
- Modify: `menubar-hub/renderer/app.js`
- Modify: `menubar-hub/renderer/index.html`
- Modify: `menubar-hub/preload.js`

- [ ] **Step 1: main.js — load-or-init + roster hook**

In `app.whenReady`, change:

```js
  settings = settingsModule.load(app.getPath('userData'));
```
to:
```js
  settings = settingsModule.loadOrInit(app.getPath('userData'));
```

In `buildClient`, replace the `state` init and the `onPeer` hook:

```js
  state = { relay: 'connecting', peer: false, roster: [] };
```
```js
    onRoster: (phones) => {
      state.roster = phones; state.peer = phones.length > 0;
      pushToRenderer('hub:roster', phones); updateTrayTitle();
    },
```
(remove the old `onPeer:` line.)

- [ ] **Step 2: preload.js — expose onRoster**

Add an `onRoster` channel mirroring the existing `onPeer`/`onLog` exposure (open `preload.js`, copy the `onLog` pattern):

```js
  onRoster: (cb) => ipcRenderer.on('hub:roster', (_e, phones) => cb(phones)),
```
Keep `onPeer` if present (harmless); it just won't fire.

- [ ] **Step 3: index.html — editable code input + roster list**

Change the pairing-code display to an editable input (replace the `<span id="code">` element) and add a roster `<ul>`:

```html
<input id="code" type="text" autocapitalize="none" autocorrect="off" spellcheck="false" />
<ul id="roster"></ul>
```

- [ ] **Step 4: app.js — code save, roster render, log attribution**

In `init()`, set the input value from settings (`$('code').value = s.pairingCode;`), and:

```js
  window.hub.onRoster(renderRoster);

  $('save').onclick = async () => {
    const updated = await window.hub.setSettings({
      relayUrl: $('relayUrl').value.trim(),
      ma3Host: $('ma3Host').value.trim(),
      ma3Port: parseInt($('ma3Port').value, 10),
      ma3Prefix: $('ma3Prefix').value.trim(),
      pairingCode: $('code').value.trim().toLowerCase(),
    });
    $('code').value = updated.pairingCode;
  };
```

Update `regen`/`copy` to use `.value` instead of `.textContent`. Add:

```js
function renderRoster(phones) {
  const ul = $('roster');
  ul.innerHTML = '';
  for (const p of phones) {
    const li = document.createElement('li');
    li.textContent = p.name;
    ul.appendChild(li);
  }
}
```

In `addLog`, prepend the operator name when present:

```js
  const who = entry.name ? entry.name + ' · ' : '';
  li.querySelector('.summary').textContent = who + entry.summary;
```

- [ ] **Step 5: Verify by build/run**

Run: `cd menubar-hub && npm test` (logic tests still green), then `npm start` and confirm the popover shows an editable code field and an (empty) roster list, and the app launches without error. Close it.
Expected: launches; code field editable; no console errors.

- [ ] **Step 6: Commit**

```bash
git add menubar-hub/main.js menubar-hub/preload.js menubar-hub/renderer/
git commit -m "feat(hub): persist code on launch, editable code, roster + attribution UI"
```

---

### Task 7: iOS messages — join name, roster/joined(cid), Operator type

Add the operator identity to the join frame and decode the roster + cid-carrying joined frame.

**Files:**
- Modify: `ios/Sources/Kit/Hub/HubMessages.swift`
- Test: `ios/Tests/KitTests/RelayModeTests.swift`

- [ ] **Step 1: Update the relay message tests**

In `RelayModeTests.swift`, update the join test and `testDecodeJoined`, and add roster tests:

```swift
func testJoinFrameEncodesRoleRoomAndName() throws {
    let json = try OutgoingMessage.join(room: "code1234", role: "phone", name: "Matteo's iPhone").jsonString()
    XCTAssertTrue(json.contains("\"type\":\"join\""))
    XCTAssertTrue(json.contains("\"room\":\"code1234\""))
    XCTAssertTrue(json.contains("\"role\":\"phone\""))
    XCTAssertTrue(json.contains("\"name\":\"Matteo's iPhone\""))
}

func testDecodeJoinedWithCid() throws {
    let msg = try IncomingMessage.decode("{\"type\":\"joined\",\"cid\":\"p1\"}")
    XCTAssertEqual(msg, .joined(cid: "p1"))
}

func testDecodeRoster() throws {
    let msg = try IncomingMessage.decode(
        "{\"type\":\"roster\",\"hub\":true,\"phones\":[{\"cid\":\"p1\",\"name\":\"Matteo\"}]}")
    XCTAssertEqual(msg, .roster(hub: true, phones: [Operator(cid: "p1", name: "Matteo")]))
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: FAIL to compile (`name:` arg, `.joined(cid:)`, `.roster`, `Operator` don't exist).

- [ ] **Step 3: Update `HubMessages.swift`**

Add the `Operator` type near `PulledSequence`:

```swift
/// One connected operator in the relay roster.
public struct Operator: Equatable, Sendable, Decodable, Identifiable {
    public let cid: String
    public let name: String
    public var id: String { cid }
    public init(cid: String, name: String) { self.cid = cid; self.name = name }
}
```

Change the `join` case + its encodable struct:

```swift
    case join(room: String, role: String, name: String?)
```
```swift
    private struct Join: Encodable { let type = "join"; let room: String; let role: String; let name: String? }
```
```swift
        case let .join(room, role, name):
            return try enc.encode(Join(room: room, role: role, name: name))
```

In `IncomingMessage`, change `joined` and add `roster` (keep legacy `peer` decoding):

```swift
    case joined(cid: String?)                        // relay: joined; phone gets a cid
    case roster(hub: Bool, phones: [Operator])       // relay: who's connected (+ hub presence)
```

Extend `Envelope` and `decode`:

```swift
        let cid: String?
        let hub: Bool?
        let phones: [Operator]?
```
```swift
        case "joined":     return .joined(cid: e.cid)
        case "roster":     return .roster(hub: e.hub ?? false, phones: e.phones ?? [])
```

- [ ] **Step 3b: Keep `HubClient.swift` compiling (minimal)**

Two edits so the Kit target still builds (Task 8 replaces them with real behavior):

In `connect()`, update the join call site to satisfy the new signature:

```swift
                    if let join = try? OutgoingMessage.join(room: self.pairingCode, role: "phone", name: nil).jsonString() {
                        conn.send(join)
                    }
```

In `handle(_:)`, add a `.roster` case so the switch stays exhaustive (the existing `case .joined: break` already matches `.joined(cid:)` ignoring its payload):

```swift
        case .roster:
            break
```

- [ ] **Step 4: Run and confirm pass**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: PASS (message tests green; Kit compiles).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Hub/HubMessages.swift ios/Sources/Kit/Hub/HubClient.swift ios/Tests/KitTests/RelayModeTests.swift
git commit -m "feat(ios): join name + roster/joined(cid) messages + Operator"
```

---

### Task 8: iOS HubClient — roster state, identity, auto-reconnect

Derive online state from the roster, expose the roster + own cid, send the device name on join, and auto-reconnect with backoff (injectable scheduler for tests).

**Files:**
- Modify: `ios/Sources/Kit/Hub/HubClient.swift`
- Test: `ios/Tests/KitTests/HubClientTests.swift` (and existing `RelayModeTests.swift` peer test)

- [ ] **Step 1: Write the new behavior tests**

Add to `HubClientTests.swift` (uses the file's existing `MockHubConnection`/`makeClient`; add a counting factory for reconnect):

```swift
func testRosterDrivesOnlineState() {
    let (client, mock) = makeClient()
    client.mode = .relay; client.relayURL = "wss://x"; client.pairingCode = "code1234"
    client.connect(); mock.emit(.opened)
    XCTAssertEqual(client.state, .connecting)
    mock.emit(.text("{\"type\":\"roster\",\"hub\":true,\"phones\":[{\"cid\":\"p1\",\"name\":\"Matteo\"}]}"))
    XCTAssertEqual(client.state, .online)
    XCTAssertEqual(client.roster, [Operator(cid: "p1", name: "Matteo")])
    mock.emit(.text("{\"type\":\"roster\",\"hub\":false,\"phones\":[]}"))
    XCTAssertEqual(client.state, .connecting)
}

func testJoinSendsOperatorName() {
    let (client, mock) = makeClient()
    client.mode = .relay; client.relayURL = "wss://x"; client.pairingCode = "code1234"
    client.operatorName = "Matteo's iPhone"
    client.connect(); mock.emit(.opened)
    XCTAssertTrue(mock.sent.contains { $0.contains("\"name\":\"Matteo's iPhone\"") })
}

func testAutoReconnectAfterCloseInRelayMode() {
    var conns: [MockHubConnection] = []
    var scheduled: [() -> Void] = []
    let d = UserDefaults(suiteName: "cc-test-\(UUID().uuidString)")!
    let client = HubClient(defaults: d,
                           makeConnection: { _ in let m = MockHubConnection(); conns.append(m); return m },
                           scheduleAfter: { _, work in scheduled.append(work) })
    client.mode = .relay; client.relayURL = "wss://x"; client.pairingCode = "code1234"
    client.connect()
    XCTAssertEqual(conns.count, 1)
    conns[0].emit(.closed(nil))
    XCTAssertEqual(scheduled.count, 1)     // a reconnect was scheduled
    scheduled[0]()                          // fire it
    XCTAssertEqual(conns.count, 2)          // reconnected with a fresh connection
}

func testNoReconnectAfterManualDisconnect() {
    var conns: [MockHubConnection] = []
    var scheduled: [() -> Void] = []
    let d = UserDefaults(suiteName: "cc-test-\(UUID().uuidString)")!
    let client = HubClient(defaults: d,
                           makeConnection: { _ in let m = MockHubConnection(); conns.append(m); return m },
                           scheduleAfter: { _, work in scheduled.append(work) })
    client.mode = .relay; client.relayURL = "wss://x"; client.pairingCode = "code1234"
    client.connect()
    client.disconnect()
    conns[0].emit(.closed(nil))
    XCTAssertEqual(scheduled.count, 0)     // user asked to stop; don't reconnect
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: FAIL (no `operatorName`, `roster`, `disconnect`, `scheduleAfter`).

- [ ] **Step 3: Update `HubClient.swift`**

Add stored properties (near the other `@ObservationIgnored` / public vars):

```swift
    public private(set) var roster: [Operator] = []
    public var operatorName: String = ""

    @ObservationIgnored private let scheduleAfter: (TimeInterval, @escaping () -> Void) -> Void
    @ObservationIgnored private var ownCid: String?
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var backoff: TimeInterval = 1
```

Change the initializer signature + body:

```swift
    public init(defaults: UserDefaults = .standard,
                makeConnection: @escaping (URL) -> HubConnection,
                scheduleAfter: @escaping (TimeInterval, @escaping () -> Void) -> Void
                    = { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }) {
        self.scheduleAfter = scheduleAfter
        self.defaults = defaults
        self.makeConnection = makeConnection
        self.host = defaults.string(forKey: Keys.host) ?? ""
        let p = defaults.integer(forKey: Keys.port)
        self.port = p == 0 ? 9000 : p
        self.mode = HubMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .direct
        self.relayURL = defaults.string(forKey: Keys.relayURL) ?? ""
        self.pairingCode = defaults.string(forKey: Keys.pairingCode) ?? ""
    }
```

In `connect()`, reset `stopped` at the top (`stopped = false`) and send the name on join:

```swift
                    if let join = try? OutgoingMessage.join(room: self.pairingCode, role: "phone",
                                                            name: self.operatorName.isEmpty ? nil : self.operatorName).jsonString() {
                        conn.send(join)
                    }
```

In the `case let .closed(reason):` branch, add the reconnect scheduling for relay mode:

```swift
            case let .closed(reason):
                self.state = reason.map(ConnectionState.error) ?? .offline
                if self.mode == .relay && !self.stopped { self.scheduleReconnect() }
```

Add a `disconnect()` and `scheduleReconnect()`:

```swift
    public func disconnect() {
        stopped = true
        connection?.close()
        connection = nil
        state = .offline
    }

    private func scheduleReconnect() {
        let wait = backoff
        backoff = min(backoff * 2, 15)
        scheduleAfter(wait) { [weak self] in
            guard let self, !self.stopped else { return }
            self.connect()
        }
    }
```

In `handle(_:)`, replace the `.joined`/`.peer` cases and the placeholder `.roster` case (from Task 7) with the real behavior:

```swift
        case let .joined(cid):
            ownCid = cid                            // remember our id for self-marking
        case let .roster(hub, phones):
            roster = phones
            if mode == .relay { state = hub ? .online : .connecting }
            if hub { backoff = 1 }                  // healthy link → reset backoff
        case let .peer(connected):                  // legacy relay; harmless if it arrives
            if mode == .relay { state = connected ? .online : .connecting }
```

(Leave `.joinError` setting `stopped = true` so we don't hammer a rejected room — add `stopped = true` inside that case.)

- [ ] **Step 4: Run and confirm pass**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: PASS (all Kit tests green).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Hub/HubClient.swift ios/Tests/KitTests/HubClientTests.swift
git commit -m "feat(ios): roster-driven state, device-name identity, auto-reconnect"
```

---

### Task 9: iOS app — set device name + roster view

Pass the device name into the client and surface the connected-operators roster in the UI.

**Files:**
- Modify: `ios/Sources/App/App.swift`
- Modify: `ios/Sources/App/SettingsView.swift`

- [ ] **Step 1: App.swift — set operator name before connect**

Add `import UIKit` and set the name in `.onAppear`:

```swift
                .onAppear {
                    hub.operatorName = UIDevice.current.name
                    if !hub.host.isEmpty || hub.mode == .relay { hub.connect() }
                }
```

- [ ] **Step 2: SettingsView.swift — roster section**

In the relay section of `SettingsView.swift`, add a roster readout bound to `hub.roster` (match the file's existing `@Environment(HubClient.self)` access and Section/Form style):

```swift
if !hub.roster.isEmpty {
    Section("Connected") {
        ForEach(hub.roster) { op in
            Text(op.name)
        }
    }
}
```

- [ ] **Step 3: Build the app**

Run: `cd ios && xcodegen generate && xcodebuild build -scheme Saetta -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App/App.swift ios/Sources/App/SettingsView.swift
git commit -m "feat(ios): device-name identity + connected-operators roster view"
```

---

### Task 10: Full-suite verification

- [ ] **Step 1: Run every suite**

```bash
cd relay && npm test && cd ../menubar-hub && npm test && cd ../hub && npm test
cd ../ios && xcodegen generate \
  && xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5 \
  && xcodebuild build -scheme Saetta -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```
Expected: all green; BUILD SUCCEEDED.

- [ ] **Step 2: Confirm branch state**

```bash
git -C /Users/jordanbabev/cuelist-compiler log --oneline -12
git -C /Users/jordanbabev/cuelist-compiler status -sb
```
Expected: clean tree on `feat/multi-phone-hub` with all task commits.

---

## Deferred to on-device smoke / rollout (NOT in this plan)

These require real hardware and a coordinated deploy — track them, don't implement here:
- Deploy the new relay to Fly (`cd relay && fly deploy`).
- Build + ship the new Saetta Hub DMG; install the new iOS app on Matteo's + Francesco's phones.
- Multi-phone on-desk smoke: two phones, one hub, both fire to the desk; roster + attribution show; pull/compile route to the right phone only; relay restart → both auto-reconnect hands-free.
- Rotate the exposed notary app-specific password.

## Out of scope (YAGNI)

LAN-hub multi-phone, QR pairing, command echo between phones, per-operator locking/queueing/hand-off, custom names beyond the device name.
