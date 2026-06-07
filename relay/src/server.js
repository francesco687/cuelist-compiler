'use strict';
const http = require('node:http');
const { WebSocketServer } = require('ws');
const { Rooms } = require('./rooms');

const MAX_FRAME = 256 * 1024;        // 256 KB cap — shows are small JSON
const DEFAULT_JOIN_TIMEOUT_MS = 5000;
const HEARTBEAT_MS = 25000;          // keep Fly from idling the socket

function startRelay({ port, host, joinTimeoutMs = DEFAULT_JOIN_TIMEOUT_MS } = {}) {
  const rooms = new Rooms();

  const server = http.createServer((req, res) => {
    if (req.url === '/healthz') { res.writeHead(200); res.end('ok'); return; }
    res.writeHead(426); res.end('upgrade required');
  });
  const wss = new WebSocketServer({ server, maxPayload: MAX_FRAME });

  wss.on('connection', (ws) => {
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });

    let joined = false;
    const joinTimer = setTimeout(() => { if (!joined) ws.close(); }, joinTimeoutMs);

    ws.on('message', (raw) => {
      const text = raw.toString();
      if (!joined) {
        let msg;
        try { msg = JSON.parse(text); } catch { return ws.close(); }
        if (msg.type !== 'join') return ws.close();
        const res = rooms.join(ws, msg.room, msg.role, msg.name);
        if (!res.ok) { try { ws.send(JSON.stringify({ type: 'join-error', message: res.error })); } catch {} return ws.close(); }
        joined = true;
        clearTimeout(joinTimer);
        return;
      }
      rooms.forward(ws, text);  // opaque passthrough
    });

    ws.on('close', () => { clearTimeout(joinTimer); rooms.leave(ws); });
    ws.on('error', () => { /* a 'close' will follow */ });
  });

  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (ws.isAlive === false) { ws.terminate(); continue; }
      ws.isAlive = false;
      try { ws.ping(); } catch {}
    }
  }, HEARTBEAT_MS);

  // Omitting host lets Node bind all interfaces (0.0.0.0 / ::) AND makes
  // server.address() available synchronously after listen(); passing an
  // explicit host defers binding to the next tick (address() returns null).
  if (host) server.listen(port, host); else server.listen(port);

  return {
    server, wss, rooms,
    close() {
      clearInterval(heartbeat);
      return new Promise((resolve) => { wss.close(() => server.close(resolve)); });
    },
  };
}

module.exports = { startRelay };
