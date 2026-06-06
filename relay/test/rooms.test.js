'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const { Rooms } = require('../src/rooms');

// Fake socket: records every string passed to .send().
function fakeSocket() { const out = []; return { out, send: (s) => out.push(JSON.parse(s)) }; }

test('matching code bridges hub and phone, both told peer connected', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), phone = fakeSocket();
  assert.deepStrictEqual(rooms.join(hub, 'ABC12345', 'hub'), { ok: true });
  assert.deepStrictEqual(hub.out, [{ type: 'joined' }]);
  assert.deepStrictEqual(rooms.join(phone, 'ABC12345', 'phone'), { ok: true });
  // phone gets joined + peer; hub gets a peer-connected too
  assert.deepStrictEqual(phone.out, [{ type: 'joined' }, { type: 'peer', connected: true }]);
  assert.deepStrictEqual(hub.out, [{ type: 'joined' }, { type: 'peer', connected: true }]);
});

test('forward relays raw text verbatim to the peer only', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), phone = fakeSocket();
  rooms.join(hub, 'ROOMCODE1', 'hub');
  rooms.join(phone, 'ROOMCODE1', 'phone');
  hub.out.length = 0; phone.out.length = 0;
  rooms.forward(phone, JSON.stringify({ type: 'cmd', line: 'Go+' }));
  assert.deepStrictEqual(hub.out, [{ type: 'cmd', line: 'Go+' }]);
  assert.deepStrictEqual(phone.out, []);
});

test('second hub in a full room is rejected', () => {
  const rooms = new Rooms();
  rooms.join(fakeSocket(), 'ROOMCODE1', 'hub');
  assert.deepStrictEqual(rooms.join(fakeSocket(), 'ROOMCODE1', 'hub'), { ok: false, error: 'role taken' });
});

test('mismatched codes never bridge', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), phone = fakeSocket();
  rooms.join(hub, 'CODE-AAAA', 'hub');
  rooms.join(phone, 'CODE-BBBB', 'phone');
  rooms.forward(phone, JSON.stringify({ type: 'cmd', line: 'Go+' }));
  assert.deepStrictEqual(hub.out, [{ type: 'joined' }]); // never received the cmd
});

test('leave notifies the surviving peer', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), phone = fakeSocket();
  rooms.join(hub, 'ROOMCODE1', 'hub');
  rooms.join(phone, 'ROOMCODE1', 'phone');
  hub.out.length = 0;
  rooms.leave(phone);
  assert.deepStrictEqual(hub.out, [{ type: 'peer', connected: false }]);
});

test('too-short code is rejected', () => {
  const rooms = new Rooms();
  assert.deepStrictEqual(rooms.join(fakeSocket(), 'short', 'hub'), { ok: false, error: 'bad room' });
});
