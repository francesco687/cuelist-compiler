'use strict';
const { WebSocketServer } = require('ws');
const { createContext, handleMessage } = require('./handle');

/**
 * Starts the hub WebSocket server. Returns { wss, close() }.
 * One shared compiler context + one UDP sender are reused across connections.
 */
function startServer(config) {
  const ctx = createContext(config);
  const wss = new WebSocketServer({ host: config.host, port: config.port });

  const send = (ws, obj) => { try { ws.send(JSON.stringify(obj)); } catch { /* socket gone */ } };

  wss.on('connection', (ws) => {
    ws.on('message', async (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); }
      catch { return send(ws, { type: 'error', message: 'invalid JSON' }); }
      await handleMessage(ctx, msg, (obj) => send(ws, obj));
    });
  });

  return {
    wss,
    close() {
      return new Promise((resolve) => {
        for (const client of wss.clients) client.terminate();
        ctx.sender.close();
        wss.close(resolve);
      });
    },
  };
}

module.exports = { startServer };
