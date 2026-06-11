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

test('a retired client does not clobber shared state when its socket closes late', () => {
  // Repro of the "online but shows offline" bug: buildClient() replaces a client
  // (regen / settings save / post-deploy reconnect). The old client is close()'d,
  // but its half-open socket fires 'close' LATE — after the new client is already
  // online. A retired client must NOT push 'offline'/[] through the shared hooks.
  const sock = new FakeSocket();
  const { core } = fakeDeps();
  const states = [];
  const rosters = [];
  const c = new RelayHubClient(config,
    { onState: (s) => states.push(s), onRoster: (p) => rosters.push(p) },
    { makeSocket: () => sock, core });
  c.connect();
  sock.emit('open');            // 'connecting' -> 'online'
  c.close();                    // retire it; close() triggers a late socket 'close'
  assert.ok(!states.includes('offline'),
    `retired client clobbered state with 'offline': ${JSON.stringify(states)}`);
  assert.ok(!rosters.some((r) => r.length === 0),
    `retired client clobbered the roster with []: ${JSON.stringify(rosters)}`);
});

test('a live client DOES emit offline and reconnects when its socket drops', () => {
  const sock = new FakeSocket();
  const { core } = fakeDeps();
  const states = [];
  const c = new RelayHubClient(config, { onState: (s) => states.push(s) }, { makeSocket: () => sock, core });
  c.connect();
  sock.emit('open');            // 'connecting' -> 'online'
  sock.emit('close');           // server dropped us while still live
  assert.ok(states.includes('offline'), `live drop should surface 'offline': ${JSON.stringify(states)}`);
  c.close();                    // stop the scheduled reconnect timer so the test exits clean
});

test('control frames (joined/roster) are NOT forwarded to handleMessage', async () => {
  const sock = new FakeSocket();
  const { osc, core } = fakeDeps();
  const c = new RelayHubClient(config, {}, { makeSocket: () => sock, core });
  c.connect(); sock.emit('open');
  sock.emit('message', Buffer.from(JSON.stringify({ type: 'joined' })));
  await new Promise((r) => setTimeout(r, 0));
  assert.deepStrictEqual(osc, []);
});

test('kickAll broadcasts a bare kicked frame; safe no-op before connect', () => {
  const sock = new FakeSocket();
  const { core } = fakeDeps();
  const c = new RelayHubClient(config, {}, { makeSocket: () => sock, core });
  c.kickAll();                                  // no socket yet — must not throw, must not send
  c.connect();
  sock.emit('open');
  c.kickAll();
  // sent[0] is the join frame from 'open'; the kick must be the bare un-enveloped frame
  assert.deepStrictEqual(sock.sent.at(-1), { type: 'kicked' });
  assert.strictEqual(sock.sent.length, 2);      // exactly join + kicked (pre-connect call sent nothing)
});
