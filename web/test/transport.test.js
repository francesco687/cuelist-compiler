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
