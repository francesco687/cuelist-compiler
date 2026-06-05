// transport.js — selects how per-line OSC commands leave the app.
// Electron: over IPC to the main process (native UDP). Browser: WebSocket to proxy.
// Exposes CC.transport.make(win, opts). Depends on: nothing (constants passed in).

(function () {
  function makeElectron(win) {
    const t = {
      kind: 'electron',
      status: 'offline',
      onStatus: null,
      onMessage: null,
      _set(s) { this.status = s; if (this.onStatus) this.onStatus(s); },
      connect() { this._set('online'); return Promise.resolve(); }, // main owns the socket
      sendLine(line) { return win.cuelist.sendLine(line); },
    };
    return t;
  }

  function makeWebSocket(win, opts) {
    const url = (opts && opts.proxyUrl);
    let ws = null;
    const t = {
      kind: 'websocket',
      status: 'offline',
      onStatus: null,
      onMessage: null,
      _set(s) { this.status = s; if (this.onStatus) this.onStatus(s); },
      connect() {
        return new Promise((resolve) => {
          this._set('connecting');
          try {
            ws = new win.WebSocket(url);
          } catch (e) {
            this._set('offline');
            resolve();
            return;
          }
          ws.addEventListener('open', () => { this._set('online'); resolve(); });
          ws.addEventListener('close', () => { this._set('offline'); });
          ws.addEventListener('error', () => { /* 'close' fires after; nothing to do */ });
          ws.addEventListener('message', (ev) => {
            let msg;
            try { msg = JSON.parse(ev.data); } catch (e) { return; }
            if (this.onMessage) this.onMessage(msg);
          });
        });
      },
      sendLine(line) {
        return new Promise((resolve, reject) => {
          if (!ws || ws.readyState !== win.WebSocket.OPEN) { reject(new Error('OSC offline')); return; }
          try { ws.send(JSON.stringify({ type: 'cmd', line })); resolve(); }
          catch (e) { reject(e); }
        });
      },
    };
    return t;
  }

  function make(win, opts) {
    return (win && win.cuelist && win.cuelist.isDesktop)
      ? makeElectron(win)
      : makeWebSocket(win, opts);
  }

  window.CC = window.CC || {};
  window.CC.transport = { make };
})();
