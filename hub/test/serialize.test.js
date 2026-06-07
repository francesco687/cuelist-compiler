'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const { createMutex } = require('../src/serialize');

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

test('createMutex runs tasks one at a time in call order', async () => {
  const run = createMutex();
  const order = [];
  const a = run(async () => { await delay(20); order.push('a'); });
  const b = run(async () => { await delay(1); order.push('b'); });
  await Promise.all([a, b]);
  assert.deepStrictEqual(order, ['a', 'b']);   // b waited for a despite being faster
});

test('a failing task does not break the chain', async () => {
  const run = createMutex();
  const order = [];
  const a = run(async () => { throw new Error('boom'); });
  await assert.rejects(a, /boom/);
  await run(async () => { order.push('b'); });
  assert.deepStrictEqual(order, ['b']);
});
