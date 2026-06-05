'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Load transport.js into a sandbox with a fake window, return its CC.transport.
function loadTransport(win) {
  const code = fs.readFileSync(path.resolve(__dirname, '..', 'js', 'transport.js'), 'utf8');
  const sandbox = { window: win, WebSocket: win.WebSocket, console };
  sandbox.window.CC = sandbox.window.CC || {};
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: 'transport.js' });
  return sandbox.window.CC.transport;
}

test('selects Electron transport when window.cuelist is present', async () => {
  const sent = [];
  const win = { cuelist: { isDesktop: true, sendLine: (l) => { sent.push(l); return Promise.resolve(); } } };
  const t = loadTransport(win).make(win);
  assert.strictEqual(t.kind, 'electron');
  await t.connect();
  assert.strictEqual(t.status, 'online'); // main owns the socket → always online
  await t.sendLine('Clear');
  assert.deepStrictEqual(sent, ['Clear']);
});

test('selects WebSocket transport when window.cuelist is absent', () => {
  const win = { WebSocket: function () { this.readyState = 0; } };
  win.WebSocket.OPEN = 1; win.WebSocket.CONNECTING = 0;
  const t = loadTransport(win).make(win, { proxyUrl: 'ws://127.0.0.1:8765' });
  assert.strictEqual(t.kind, 'websocket');
});

test('WebSocket transport: connect→open goes online, sendLine emits the cmd frame, pre-open send rejects', async () => {
  let lastSocket = null;
  function FakeWebSocket(url) {
    this.url = url;
    this.readyState = FakeWebSocket.CONNECTING;
    this.handlers = {};
    this.sent = [];
    lastSocket = this;
  }
  FakeWebSocket.OPEN = 1;
  FakeWebSocket.CONNECTING = 0;
  FakeWebSocket.prototype.addEventListener = function (event, cb) {
    (this.handlers[event] || (this.handlers[event] = [])).push(cb);
  };
  FakeWebSocket.prototype.fire = function (event, ev) {
    (this.handlers[event] || []).forEach((cb) => cb(ev));
  };
  FakeWebSocket.prototype.send = function (data) { this.sent.push(data); };

  const win = { WebSocket: FakeWebSocket };
  const t = loadTransport(win).make(win, { proxyUrl: 'ws://x' });
  assert.strictEqual(t.kind, 'websocket');

  // Before connect/open: sendLine rejects mentioning 'offline'.
  await assert.rejects(() => t.sendLine('Early'), /offline/);

  const statuses = [];
  t.onStatus = (s) => statuses.push(s);

  const connected = t.connect();
  assert.strictEqual(lastSocket.url, 'ws://x');

  // Simulate the socket opening.
  lastSocket.readyState = FakeWebSocket.OPEN;
  lastSocket.fire('open');

  await connected; // connect promise resolves on open
  assert.strictEqual(t.status, 'online');
  assert.deepStrictEqual(statuses, ['connecting', 'online']);

  // sendLine now emits exactly the cmd frame.
  await t.sendLine('Go');
  assert.deepStrictEqual(lastSocket.sent, [JSON.stringify({ type: 'cmd', line: 'Go' })]);
});
