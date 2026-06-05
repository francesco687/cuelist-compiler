'use strict';
const { WebSocketServer } = require('ws');
const { OscSender } = require('./osc');
const { createCompiler, compileShow } = require('./compile-bridge');
const { pullSequences } = require('./pull');

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Starts the hub WebSocket server. Returns { wss, close() }.
 * One shared compiler context + one UDP sender are reused across connections.
 */
function startServer(config) {
  const api = createCompiler({ webJsDir: config.webJsDir });
  const sender = new OscSender({ host: config.ma3Host, port: config.ma3Port, prefix: config.ma3Prefix });
  const wss = new WebSocketServer({ host: config.host, port: config.port });

  const send = (ws, obj) => { try { ws.send(JSON.stringify(obj)); } catch { /* socket gone */ } };

  // Single-operator hub: relays are NOT serialized across connections. compileShow is
  // synchronous so the compiler's VM state can't corrupt mid-compile, but two overlapping
  // compile-send relays would interleave OSC datagrams on the wire. Acceptable for one phone;
  // if a second client is ever added, gate concurrent compile-send with an in-flight flag.
  async function relayLines(ws, lines) {
    for (let i = 0; i < lines.length; i++) {
      await sender.send(lines[i]);
      send(ws, { type: 'progress', sent: i + 1, total: lines.length });
      if (i < lines.length - 1) await delay(config.intervalMs);
    }
    send(ws, { type: 'done', total: lines.length });
  }

  wss.on('connection', (ws) => {
    ws.on('message', async (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); }
      catch { return send(ws, { type: 'error', message: 'invalid JSON' }); }

      if (msg.type === 'compile-send') {
        let lines;
        try {
          lines = compileShow(api, {
            project: msg.project, defaults: msg.defaults, selection: msg.selection || 'all',
          });
        } catch (e) {
          return send(ws, { type: 'error', message: e.message });
        }
        try { await relayLines(ws, lines); }
        catch (e) { send(ws, { type: 'error', message: e.message }); }
      } else if (msg.type === 'cmd' && typeof msg.line === 'string') {
        try { await sender.send(msg.line); send(ws, { type: 'sent', line: msg.line }); }
        catch (e) { send(ws, { type: 'error', message: e.message }); }
      } else if (msg.type === 'pull-sequences') {
        // Fire the desk plugin, wait for the file it writes, relay the list back.
        try {
          const data = await pullSequences({
            sender,
            trigger: config.pullTrigger,
            file: config.pullFile,
            timeoutMs: config.pullTimeoutMs,
          });
          send(ws, { type: 'sequences', version: data.version ?? 1, sequences: data.sequences });
        } catch (e) {
          send(ws, { type: 'pull-error', message: e.message });
        }
      } else if (msg.type === 'ping') {
        send(ws, { type: 'pong' });
      } else {
        send(ws, { type: 'error', message: 'unknown message' });
      }
    });
  });

  return {
    wss,
    close() {
      return new Promise((resolve) => {
        for (const client of wss.clients) client.terminate();
        sender.close();
        wss.close(resolve);
      });
    },
  };
}

module.exports = { startServer };
