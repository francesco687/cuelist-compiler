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

async function waitFor(cond, timeoutMs) {
  const start = Date.now();
  while (!cond()) {
    if (Date.now() - start > timeoutMs) throw new Error('waitFor: condition not met within ' + timeoutMs + 'ms');
    await new Promise((r) => setTimeout(r, 5));
  }
}

test('compile-send relays datagrams that decode to the golden lines', async () => {
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

  try {
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
    await waitFor(() => datagrams.length >= golden.length, 2000);

    assert.strictEqual(doneMsg.total, golden.length);
    assert.strictEqual(datagrams.length, golden.length);
    assert.deepStrictEqual(progress, golden.map((_, i) => i + 1));
    const decoded = datagrams.map(decodeOscMessage);
    assert.ok(decoded.every((d) => d.addr === '/gma3/cmd'));
    assert.deepStrictEqual(decoded.map((d) => d.arg), golden);
  } finally {
    ws.close();
    await handle.close();
    rx.close();
  }
});

test('compile-send with empty selection returns an error', async () => {
  const handle = startServer({
    host: '127.0.0.1', port: 0, ma3Host: '127.0.0.1', ma3Port: 9, ma3Prefix: 'gma3', intervalMs: 1,
  });
  await new Promise((r) => handle.wss.on('listening', r));
  const ws = new WebSocket(`ws://127.0.0.1:${handle.wss.address().port}`);

  try {
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
  } finally {
    ws.close();
    await handle.close();
  }
});
