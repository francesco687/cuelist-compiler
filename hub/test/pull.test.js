'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const dgram = require('node:dgram');
const { startServer } = require('../src/server');
const { readPullFile } = require('../src/pull');

function decodeOscString(buf, offset) {
  let end = offset;
  while (buf[end] !== 0) end++;
  const s = buf.toString('utf8', offset, end);
  const next = offset + Math.ceil((end - offset + 1) / 4) * 4;
  return [s, next];
}
function decodeOscArg(buf) {
  const [, o1] = decodeOscString(buf, 0); // address
  const [, o2] = decodeOscString(buf, o1); // typetag
  return decodeOscString(buf, o2)[0];
}

function tmpFile() {
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'pull-')), 'sequences.json');
}

test('readPullFile parses valid, rejects missing sequences[]', () => {
  const f = tmpFile();
  fs.writeFileSync(f, '{"version":1,"sequences":[{"no":1,"name":"X"}]}');
  assert.strictEqual(readPullFile(f).sequences.length, 1);
  fs.writeFileSync(f, '{"version":1}');
  assert.throws(() => readPullFile(f), /missing sequences/);
});

test('pull-sequences: fires OSC trigger, relays the file the plugin writes', async () => {
  const file = tmpFile(); // does not exist yet
  const expected = { version: 1, sequences: [{ no: 1, name: 'ENTER SANDMAN' }, { no: 666, name: 'SONG_1' }] };

  // Stand in for the desk: when the trigger datagram arrives, write the file.
  const rx = dgram.createSocket('udp4');
  let triggerArg = null;
  rx.on('message', (m) => {
    triggerArg = decodeOscArg(Buffer.from(m));
    fs.writeFileSync(file, JSON.stringify(expected));
  });
  await new Promise((r) => rx.bind(0, '127.0.0.1', r));

  const handle = startServer({
    host: '127.0.0.1', port: 0,
    ma3Host: '127.0.0.1', ma3Port: rx.address().port, ma3Prefix: 'gma3',
    intervalMs: 1, pullFile: file, pullTrigger: 'Call Plugin 21', pullTimeoutMs: 4000,
  });
  await new Promise((r) => handle.wss.on('listening', r));
  const ws = new WebSocket(`ws://127.0.0.1:${handle.wss.address().port}`);

  try {
    const result = new Promise((resolve, reject) => {
      ws.addEventListener('message', (ev) => {
        const msg = JSON.parse(ev.data);
        if (msg.type === 'sequences') resolve(msg);
        else if (msg.type === 'pull-error' || msg.type === 'error') reject(new Error(msg.message));
      });
    });
    await new Promise((r) => ws.addEventListener('open', r));
    ws.send(JSON.stringify({ type: 'pull-sequences' }));

    const msg = await result;
    assert.strictEqual(triggerArg, 'Call Plugin 21'); // the OSC trigger really fired
    assert.strictEqual(msg.version, 1);
    assert.deepStrictEqual(msg.sequences, expected.sequences);
  } finally {
    ws.close();
    await handle.close();
    rx.close();
  }
});

test('pull-sequences: times out to pull-error when no file appears', async () => {
  const file = tmpFile(); // nobody ever writes it
  const handle = startServer({
    host: '127.0.0.1', port: 0,
    ma3Host: '127.0.0.1', ma3Port: 9, ma3Prefix: 'gma3',
    intervalMs: 1, pullFile: file, pullTrigger: 'Call Plugin 21', pullTimeoutMs: 300,
  });
  await new Promise((r) => handle.wss.on('listening', r));
  const ws = new WebSocket(`ws://127.0.0.1:${handle.wss.address().port}`);

  try {
    const result = new Promise((resolve, reject) => {
      ws.addEventListener('message', (ev) => {
        const msg = JSON.parse(ev.data);
        if (msg.type === 'pull-error') resolve(msg);
        else if (msg.type === 'sequences') reject(new Error('unexpected sequences'));
      });
    });
    await new Promise((r) => ws.addEventListener('open', r));
    ws.send(JSON.stringify({ type: 'pull-sequences' }));
    const msg = await result;
    assert.match(msg.message, /timed out/);
  } finally {
    ws.close();
    await handle.close();
  }
});
