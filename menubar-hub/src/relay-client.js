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

const CONTROL_TYPES = new Set(['joined', 'roster', 'join-error']);

/**
 * Dials the relay, joins as 'hub', and runs the shared handleMessage core for every
 * phone frame, replying back over the same relay socket. Reconnects with backoff.
 *
 * hooks: { onState(string), onRoster([{cid,name}]), onLog({kind,summary,name,at}) }
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
  _roster(phones) { this.hooks.onRoster && this.hooks.onRoster(phones); }
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
      // A retired client (replaced by buildClient on regen/settings-save, or whose
      // server VM vanished on deploy) must NOT push state through the shared hooks —
      // a late 'close' would otherwise clobber the live client's 'online' and wipe
      // its roster, leaving the badge stuck on "offline" while commands still flow.
      if (this.stopped) return;
      this._roster([]);
      this._state('offline');
      this._scheduleReconnect();
    });

    ws.on('error', () => { /* a 'close' follows */ });
  }

  async _onMessage(text) {
    if (this.stopped) return;   // retired clients must not forward/log or touch the roster
    let msg;
    try { msg = JSON.parse(text); } catch { return; }

    if (CONTROL_TYPES.has(msg.type)) {
      if (msg.type === 'roster') this._roster(msg.phones || []);
      if (msg.type === 'join-error') this._state(`error: ${msg.message}`);
      return;
    }

    if (msg.type === 'from-phone') {
      let frame;
      try { frame = JSON.parse(msg.frame); } catch { return; }
      const cid = msg.cid;
      const reply = (obj) => {
        try { this.ws.send(JSON.stringify({ type: 'to-phone', cid, frame: JSON.stringify(obj) })); } catch {}
      };
      const out = await this.core.handleMessage(this.ctx, frame, reply);
      if (out && out.kind && out.kind !== 'ping') this._log({ ...out, name: msg.name, at: Date.now() });
      return;
    }
  }

  /**
   * Soft-kick every paired phone: broadcast a bare {type:'kicked'} frame. The
   * relay forwards any non-'to-phone' hub frame to ALL phones in the room
   * (legacy single-phone broadcast path), so the deployed relay needs no
   * changes. Updated phones disconnect and stop auto-reconnecting; they can
   * rejoin at any time with the same pairing code.
   */
  kickAll() {
    if (!this.ws || this.stopped) return;
    try { this.ws.send(JSON.stringify({ type: 'kicked' })); } catch { /* socket already dying */ }
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
