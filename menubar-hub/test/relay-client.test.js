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
