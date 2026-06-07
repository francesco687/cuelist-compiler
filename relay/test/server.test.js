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
