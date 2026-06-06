'use strict';
// Pure pairing logic — no network. A "socket" is any object with .send(string).
// One hub + one phone share a room keyed by the pairing code; everything else is
// forwarded verbatim to the opposite role.

const MIN_CODE_LEN = 6;

class Rooms {
  constructor({ maxRooms = 200 } = {}) {
    this.maxRooms = maxRooms;
    this.rooms = new Map(); // code -> { hub, phone }
  }

  join(socket, code, role) {
    if (role !== 'hub' && role !== 'phone') return { ok: false, error: 'bad role' };
    if (typeof code !== 'string' || code.length < MIN_CODE_LEN) return { ok: false, error: 'bad room' };

    let room = this.rooms.get(code);
    if (!room) {
      if (this.rooms.size >= this.maxRooms) return { ok: false, error: 'relay full' };
      room = { hub: null, phone: null };
      this.rooms.set(code, room);
    }
    if (room[role]) return { ok: false, error: 'role taken' };

    room[role] = socket;
    socket._room = code;
    socket._role = role;
    socket.send(JSON.stringify({ type: 'joined' }));

    const peer = room[role === 'hub' ? 'phone' : 'hub'];
    if (peer) {
      socket.send(JSON.stringify({ type: 'peer', connected: true }));
      peer.send(JSON.stringify({ type: 'peer', connected: true }));
    }
    return { ok: true };
  }

  forward(socket, rawText) {
    const code = socket._room;
    if (!code) return;
    const room = this.rooms.get(code);
    if (!room) return;
    const peer = room[socket._role === 'hub' ? 'phone' : 'hub'];
    if (peer) peer.send(rawText);
  }

  leave(socket) {
    const code = socket._room;
    if (!code) return;
    const room = this.rooms.get(code);
    if (!room) return;
    if (room[socket._role] === socket) room[socket._role] = null;
    const peer = room[socket._role === 'hub' ? 'phone' : 'hub'];
    if (peer) peer.send(JSON.stringify({ type: 'peer', connected: false }));
    if (!room.hub && !room.phone) this.rooms.delete(code);
  }
}

module.exports = { Rooms, MIN_CODE_LEN };
