'use strict';
// Transport-agnostic core: turns one parsed phone message into OSC side effects +
// reply frames. Used by both the LAN WebSocket server (hub/src/server.js) and the
// Fly relay client (menubar-hub/src/relay-client.js). `reply(obj)` sends one JSON
// frame back toward the phone; the return value summarizes the action for logging.
const { createCompiler, compileShow } = require('./compile-bridge');
const { OscSender } = require('./osc');
const { pullSequences } = require('./pull');
const { createMutex } = require('./serialize');

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

/** Build the shared per-process context: one VM compiler + one UDP sender. */
function createContext(config) {
  const api = createCompiler({ webJsDir: config.webJsDir });
  const sender = new OscSender({ host: config.ma3Host, port: config.ma3Port, prefix: config.ma3Prefix });
  return { api, sender, config, lock: createMutex() };
}

async function handleMessage(ctx, msg, reply) {
  const { api, sender, config } = ctx;

  if (msg.type === 'compile-send') {
    return ctx.lock(async () => {
      let lines;
      try {
        lines = compileShow(api, {
          project: msg.project, defaults: msg.defaults, selection: msg.selection || 'all',
        });
      } catch (e) { reply({ type: 'error', message: e.message }); return { kind: 'error', summary: e.message }; }
      try {
        for (let i = 0; i < lines.length; i++) {
          await sender.send(lines[i]);
          reply({ type: 'progress', sent: i + 1, total: lines.length });
          if (i < lines.length - 1) await delay(config.intervalMs);
        }
        reply({ type: 'done', total: lines.length });
        return { kind: 'send', summary: `${msg.selection || 'all'} → ${lines.length} lines` };
      } catch (e) { reply({ type: 'error', message: e.message }); return { kind: 'error', summary: e.message }; }
    });
  }

  if (msg.type === 'cmd' && typeof msg.line === 'string') {
    try { await sender.send(msg.line); reply({ type: 'sent', line: msg.line }); return { kind: 'cmd', summary: msg.line }; }
    catch (e) { reply({ type: 'error', message: e.message }); return { kind: 'error', summary: e.message }; }
  }

  if (msg.type === 'pull-sequences') {
    try {
      const data = await pullSequences({
        sender, trigger: config.pullTrigger, file: config.pullFile, timeoutMs: config.pullTimeoutMs,
      });
      reply({ type: 'sequences', version: data.version ?? 1, sequences: data.sequences });
      return { kind: 'pull', summary: `${data.sequences.length} sequences` };
    } catch (e) { reply({ type: 'pull-error', message: e.message }); return { kind: 'error', summary: e.message }; }
  }

  if (msg.type === 'ping') { reply({ type: 'pong' }); return { kind: 'ping', summary: 'ping' }; }

  reply({ type: 'error', message: 'unknown message' });
  return { kind: 'error', summary: 'unknown message' };
}

module.exports = { createContext, handleMessage };
