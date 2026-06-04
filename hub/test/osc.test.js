'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const dgram = require('node:dgram');
const { oscString, buildOscMessage, OscSender } = require('../src/osc');

test('oscString pads to 4-byte boundary with null terminator', () => {
  assert.deepStrictEqual([...oscString('abc')], [97, 98, 99, 0]);          // 3+null = 4
  assert.deepStrictEqual([...oscString('abcd')], [97, 98, 99, 100, 0, 0, 0, 0]); // 4+null -> pad 8
});

test('buildOscMessage layout for ClearAll', () => {
  const msg = buildOscMessage('/gma3/cmd', ['ClearAll']);
  // addr 12 + typetag 4 + arg 12
  assert.strictEqual(msg.length, 28);
  assert.strictEqual(msg.length % 4, 0);
  assert.deepStrictEqual([...msg.subarray(0, 12)], [...Buffer.from('/gma3/cmd'), 0, 0, 0]);
  assert.deepStrictEqual([...msg.subarray(12, 16)], [...Buffer.from(',s'), 0, 0]);
});

test('OscSender delivers a datagram to a UDP listener', async () => {
  const rx = dgram.createSocket('udp4');
  const got = [];
  rx.on('message', (m) => got.push(Buffer.from(m)));
  await new Promise((r) => rx.bind(0, '127.0.0.1', r));
  const port = rx.address().port;

  const sender = new OscSender({ host: '127.0.0.1', port, prefix: 'gma3' });
  await sender.send('Group "X"');
  await new Promise((r) => setTimeout(r, 100));
  sender.close();
  rx.close();

  assert.strictEqual(got.length, 1);
  assert.deepStrictEqual([...got[0].subarray(0, 12)], [...Buffer.from('/gma3/cmd'), 0, 0, 0]);
});
