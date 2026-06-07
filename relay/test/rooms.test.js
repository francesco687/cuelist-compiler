'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const { Rooms } = require('../src/rooms');

// Fake socket: records every string passed to .send().
function fakeSocket() { const out = []; return { out, send: (s) => out.push(JSON.parse(s)) }; }

test('phone join assigns a cid and tells the hub + phones a roster', () => {
  const rooms = new Rooms();
  const hub = fakeSocket();
  assert.deepStrictEqual(rooms.join(hub, 'roomcode1', 'hub'), { ok: true });
  assert.deepStrictEqual(hub.out, [{ type: 'joined' }, { type: 'roster', phones: [] }]);

  const phone = fakeSocket();
  hub.out.length = 0;
  assert.deepStrictEqual(rooms.join(phone, 'roomcode1', 'phone', "Matteo's iPhone"), { ok: true });
  assert.deepStrictEqual(phone.out[0], { type: 'joined', cid: 'p1' });
  assert.deepStrictEqual(phone.out[1], { type: 'roster', hub: true, phones: [{ cid: 'p1', name: "Matteo's iPhone" }] });
  assert.deepStrictEqual(hub.out, [{ type: 'roster', phones: [{ cid: 'p1', name: "Matteo's iPhone" }] }]);
});

test('two phones both appear in the roster broadcast', () => {
  const rooms = new Rooms();
  const hub = fakeSocket();
  rooms.join(hub, 'roomcode1', 'hub');
  rooms.join(fakeSocket(), 'roomcode1', 'phone', 'A');
  hub.out.length = 0;
  rooms.join(fakeSocket(), 'roomcode1', 'phone', 'B');
  assert.deepStrictEqual(hub.out, [{ type: 'roster', phones: [{ cid: 'p1', name: 'A' }, { cid: 'p2', name: 'B' }] }]);
});

test('blank/missing name defaults to iPhone', () => {
  const rooms = new Rooms();
  const hub = fakeSocket();
  rooms.join(hub, 'roomcode1', 'hub');
  hub.out.length = 0;
  rooms.join(fakeSocket(), 'roomcode1', 'phone');
  assert.deepStrictEqual(hub.out[0].phones, [{ cid: 'p1', name: 'iPhone' }]);
});

test('phone frame is wrapped from-phone toward the hub only', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), phone = fakeSocket();
  rooms.join(hub, 'roomcode1', 'hub');
  rooms.join(phone, 'roomcode1', 'phone', 'Matteo');
  hub.out.length = 0; phone.out.length = 0;
  rooms.forward(phone, JSON.stringify({ type: 'cmd', line: 'Go+' }));
  assert.deepStrictEqual(hub.out, [{ type: 'from-phone', cid: 'p1', name: 'Matteo', frame: '{"type":"cmd","line":"Go+"}' }]);
  assert.deepStrictEqual(phone.out, []);
});

test('hub to-phone reply is unwrapped to the one targeted phone', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), a = fakeSocket(), b = fakeSocket();
  rooms.join(hub, 'roomcode1', 'hub');
  rooms.join(a, 'roomcode1', 'phone', 'A');   // p1
  rooms.join(b, 'roomcode1', 'phone', 'B');   // p2
  a.out.length = 0; b.out.length = 0;
  rooms.forward(hub, JSON.stringify({ type: 'to-phone', cid: 'p2', frame: '{"type":"pong"}' }));
  assert.deepStrictEqual(a.out, []);
  assert.deepStrictEqual(b.out, [{ type: 'pong' }]);
});

test('legacy un-enveloped hub frame is broadcast to all phones', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), a = fakeSocket(), b = fakeSocket();
  rooms.join(hub, 'roomcode1', 'hub');
  rooms.join(a, 'roomcode1', 'phone', 'A');
  rooms.join(b, 'roomcode1', 'phone', 'B');
  a.out.length = 0; b.out.length = 0;
  rooms.forward(hub, JSON.stringify({ type: 'sent', line: 'Go+' }));
  assert.deepStrictEqual(a.out, [{ type: 'sent', line: 'Go+' }]);
  assert.deepStrictEqual(b.out, [{ type: 'sent', line: 'Go+' }]);
});

test('room full past maxPhones is rejected', () => {
  const rooms = new Rooms({ maxPhones: 2 });
  rooms.join(fakeSocket(), 'roomcode1', 'hub');
  rooms.join(fakeSocket(), 'roomcode1', 'phone', 'A');
  rooms.join(fakeSocket(), 'roomcode1', 'phone', 'B');
  assert.deepStrictEqual(rooms.join(fakeSocket(), 'roomcode1', 'phone', 'C'), { ok: false, error: 'room full' });
});

test('second hub is still rejected', () => {
  const rooms = new Rooms();
  rooms.join(fakeSocket(), 'roomcode1', 'hub');
  assert.deepStrictEqual(rooms.join(fakeSocket(), 'roomcode1', 'hub'), { ok: false, error: 'role taken' });
});

test('leaving phone is dropped and roster rebroadcast', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), a = fakeSocket();
  rooms.join(hub, 'roomcode1', 'hub');
  rooms.join(a, 'roomcode1', 'phone', 'A');
  hub.out.length = 0;
  rooms.leave(a);
  assert.deepStrictEqual(hub.out, [{ type: 'roster', phones: [] }]);
});

test('room is deleted only when hub and all phones are gone', () => {
  const rooms = new Rooms();
  const hub = fakeSocket(), a = fakeSocket();
  rooms.join(hub, 'roomcode1', 'hub');
  rooms.join(a, 'roomcode1', 'phone', 'A');
  rooms.leave(a);
  assert.strictEqual(rooms.rooms.has('roomcode1'), true);
  rooms.leave(hub);
  assert.strictEqual(rooms.rooms.has('roomcode1'), false);
});

test('short code is rejected', () => {
  const rooms = new Rooms();
  assert.deepStrictEqual(rooms.join(fakeSocket(), 'abc', 'hub'), { ok: false, error: 'bad room' });
});
