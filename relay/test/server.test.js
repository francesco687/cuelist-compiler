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

// Per-socket buffered reader: a persistent 'message' listener queues every frame,
// so back-to-back sends (e.g. joined + peer) are never dropped. Calling the
// returned next() resolves with frames in arrival order. This fixes the race in a
// lazily-attached one-shot once() reader.
function reader(ws) {
  const queue = [];
  const waiters = [];
  ws.on('message', (m) => {
    const msg = JSON.parse(m.toString());
    if (waiters.length) waiters.shift()(msg);
    else queue.push(msg);
  });
  return () => new Promise((resolve) => {
    if (queue.length) resolve(queue.shift());
    else waiters.push(resolve);
  });
}

test('two clients with the same code exchange a forwarded frame end to end', async () => {
  const relay = startRelay({ port: 0 });
  const port = relay.server.address().port;
  const url = `ws://127.0.0.1:${port}`;

  const hub = await open(url);
  const hubNext = reader(hub);
  hub.send(JSON.stringify({ type: 'join', room: 'ENDTOEND1', role: 'hub' }));
  assert.deepStrictEqual(await hubNext(), { type: 'joined' });

  const phone = await open(url);
  const phoneNext = reader(phone);
  phone.send(JSON.stringify({ type: 'join', room: 'ENDTOEND1', role: 'phone' }));
  assert.deepStrictEqual(await phoneNext(), { type: 'joined' });
  assert.deepStrictEqual(await phoneNext(), { type: 'peer', connected: true });
  assert.deepStrictEqual(await hubNext(), { type: 'peer', connected: true });

  phone.send(JSON.stringify({ type: 'cmd', line: 'Go+' }));
  assert.deepStrictEqual(await hubNext(), { type: 'cmd', line: 'Go+' });

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
