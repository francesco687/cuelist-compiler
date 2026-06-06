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
