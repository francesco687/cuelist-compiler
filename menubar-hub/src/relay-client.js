'use strict';
// `ws` is required lazily so this module loads in dependency-free unit tests
// (the test injects `makeSocket`, so `ws` is never actually used there). The real
// Electron app installs `ws` via `npm install` and gets it at runtime.
let WebSocket;
try { WebSocket = require('ws'); } catch { /* ws absent in hermetic tests; injected makeSocket is used instead */ }
// Default core is the shared hub logic; injectable for tests. In the packaged app
// the sibling hub/ tree isn't at this relative path (it ships under Resources and
// is injected by main.js), so tolerate the require failing here.
let defaultCore;
try { defaultCore = require('../../hub/src/handle'); } catch { /* core injected in packaged build */ }

const CONTROL_TYPES = new Set(['joined', 'peer', 'join-error']);

/**
 * Dials the relay, joins as 'hub', and runs the shared handleMessage core for every
 * phone frame, replying back over the same relay socket. Reconnects with backoff.
 *
 * hooks: { onState(string), onPeer(bool), onLog({kind,summary,at}) }
 */
class RelayHubClient {
  constructor(config, hooks = {}, { makeSocket, core } = {}) {
    this.config = config;
    this.hooks = hooks;
    this.core = core || defaultCore;
    this.makeSocket = makeSocket || ((url) => new WebSocket(url));
    this.ctx = this.core.createContext(config);
    this.ws = null;
    this.stopped = false;
    this.backoff = 1000;
    this.reconnectTimer = null;
  }

  _state(s) { this.hooks.onState && this.hooks.onState(s); }
  _peer(b) { this.hooks.onPeer && this.hooks.onPeer(b); }
  _log(entry) { this.hooks.onLog && this.hooks.onLog(entry); }

  connect() {
    this.stopped = false;
    this._state('connecting');
    const ws = this.makeSocket(this.config.relayUrl);
    this.ws = ws;

    ws.on('open', () => {
      this.backoff = 1000;
      ws.send(JSON.stringify({ type: 'join', room: this.config.pairingCode, role: 'hub' }));
      this._state('online');
    });

    ws.on('message', (raw) => this._onMessage(raw.toString()));

    ws.on('close', () => {
      this._peer(false);
      this._state('offline');
      if (!this.stopped) this._scheduleReconnect();
    });

    ws.on('error', () => { /* a 'close' follows */ });
  }

  async _onMessage(text) {
    let msg;
    try { msg = JSON.parse(text); } catch { return; }

    if (CONTROL_TYPES.has(msg.type)) {
      if (msg.type === 'peer') this._peer(!!msg.connected);
      if (msg.type === 'join-error') this._state(`error: ${msg.message}`);
      return;
    }

    const reply = (obj) => { try { this.ws.send(JSON.stringify(obj)); } catch {} };
    const out = await this.core.handleMessage(this.ctx, msg, reply);
    if (out && out.kind && out.kind !== 'ping') this._log({ ...out, at: Date.now() });
  }

  _scheduleReconnect() {
    clearTimeout(this.reconnectTimer);
    const wait = this.backoff;
    this.backoff = Math.min(this.backoff * 2, 15000);
    this.reconnectTimer = setTimeout(() => { if (!this.stopped) this.connect(); }, wait);
  }

  close() {
    this.stopped = true;
    clearTimeout(this.reconnectTimer);
    try { this.ws && this.ws.close(); } catch {}
    try { this.ctx.sender.close(); } catch {}
  }
}

module.exports = { RelayHubClient };
