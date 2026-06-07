'use strict';
// Pure pairing logic — no network. A "socket" is any object with .send(string).
// One hub + many phones share a room keyed by the pairing code. Phone frames are
// wrapped {from-phone, cid, name, frame} toward the hub; the hub replies with
// {to-phone, cid, frame} and the relay unwraps + routes the inner frame to that
// one phone. An un-enveloped hub frame is broadcast (legacy single-phone hubs).

const MIN_CODE_LEN = 6;

class Rooms {
  constructor({ maxRooms = 200, maxPhones = 8 } = {}) {
    this.maxRooms = maxRooms;
    this.maxPhones = maxPhones;
    this.rooms = new Map();   // code -> { hub: socket|null, phones: Map<cid,{socket,name}> }
    this._cid = 0;
  }

  _roster(room) {
    return [...room.phones.entries()].map(([cid, p]) => ({ cid, name: p.name }));
  }

  _broadcastRoster(room) {
    const phones = this._roster(room);
    const hubPresent = !!room.hub;
    if (room.hub) room.hub.send(JSON.stringify({ type: 'roster', phones }));
    for (const { socket } of room.phones.values()) {
      socket.send(JSON.stringify({ type: 'roster', hub: hubPresent, phones }));
    }
  }

  join(socket, code, role, name) {
    if (role !== 'hub' && role !== 'phone') return { ok: false, error: 'bad role' };
    if (typeof code !== 'string' || code.length < MIN_CODE_LEN) return { ok: false, error: 'bad room' };

    let room = this.rooms.get(code);
    if (!room) {
      if (this.rooms.size >= this.maxRooms) return { ok: false, error: 'relay full' };
      room = { hub: null, phones: new Map() };
      this.rooms.set(code, room);
    }

    if (role === 'hub') {
      if (room.hub) return { ok: false, error: 'role taken' };
      room.hub = socket;
      socket._room = code; socket._role = 'hub';
      socket.send(JSON.stringify({ type: 'joined' }));
      this._broadcastRoster(room);
      return { ok: true };
    }

    if (room.phones.size >= this.maxPhones) return { ok: false, error: 'room full' };
    const cid = 'p' + (++this._cid);
    const trimmed = typeof name === 'string' ? name.trim() : '';
    const clean = trimmed || 'iPhone';
    room.phones.set(cid, { socket, name: clean });
    socket._room = code; socket._role = 'phone'; socket._cid = cid;
    socket.send(JSON.stringify({ type: 'joined', cid }));
    this._broadcastRoster(room);
    return { ok: true };
  }

  forward(socket, rawText) {
    const code = socket._room;
    if (!code) return;
    const room = this.rooms.get(code);
    if (!room) return;

    if (socket._role === 'phone') {
      if (!room.hub) return;
      const entry = room.phones.get(socket._cid);
      room.hub.send(JSON.stringify({ type: 'from-phone', cid: socket._cid, name: entry && entry.name, frame: rawText }));
      return;
    }

    // hub -> phone(s)
    let msg;
    try { msg = JSON.parse(rawText); } catch { msg = null; }
    if (msg && msg.type === 'to-phone') {
      const target = room.phones.get(msg.cid);
      if (target && typeof msg.frame === 'string') target.socket.send(msg.frame);
      return;
    }
    for (const { socket: ps } of room.phones.values()) ps.send(rawText);   // legacy broadcast
  }

  leave(socket) {
    const code = socket._room;
    if (!code) return;
    const room = this.rooms.get(code);
    if (!room) return;
    if (socket._role === 'hub' && room.hub === socket) room.hub = null;
    if (socket._role === 'phone') room.phones.delete(socket._cid);
    if (!room.hub && room.phones.size === 0) { this.rooms.delete(code); return; }
    this._broadcastRoster(room);
  }
}

module.exports = { Rooms, MIN_CODE_LEN };
