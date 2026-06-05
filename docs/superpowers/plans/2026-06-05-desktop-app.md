# Desktop App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a cross-platform Electron desktop app that packages the existing `web/` authoring UI, sends OSC/UDP directly to a grandMA3 desk, and embeds the `hub/` WebSocket server so it fully replaces the Raspberry Pi (the iPhone connects to the laptop instead).

**Architecture:** Electron app under `desktop/`. The **renderer** is the unchanged `web/` app — it already compiles client-side (`buildCmdLines`) and sends per-line `cmd` messages. A new **transport seam** routes those per-line sends to either the WebSocket proxy (plain browser, dev fallback) or, in Electron, over IPC to the **main process**, which OSC-encodes and fires UDP via the reused `hub/src/osc.js` `OscSender`. For the iPhone companion, main starts the reused `hub/src/server.js` `startServer()` (which compiles via the VM and relays) — same protocol, port 9000.

**Tech Stack:** Electron, `electron-builder`, Node `dgram` (via `hub/src/osc.js`), `ws` (via `hub/src/server.js`), jsdom + `node --test` for renderer-seam tests.

---

## Prerequisite (HARD — read before Task 1)

**Branch reality (updated 2026-06-05):** `main` was fast-forwarded to the old `v2` tip (`348b773`); `main == v2 == 348b773` and the original line is preserved as `old-version`. PR #1 auto-merged. This branch (`feat/desktop-app`) is based on `348b773`, so **its base is already the `main` line** — no base rebase needed. **Branch new work off `main` going forward.**

What's still missing is `hub/`: `main` (`348b773`) **does not yet contain `hub/`** — `hub/` lives on `feat/ios-shell` (PR #2, now open into `main`, not yet merged). The desktop app `require()`s `hub/src/*`, so `hub/` MUST be on the branch before any task runs.

**Resolve one of these before Task 1, then verify `ls hub/src` shows `osc.js server.js compile-bridge.js config.js index.js`:**

- **Preferred:** wait for PR #2 (`feat/ios-shell` → `main`) to merge, then `git rebase main` this branch.
- **Unblock early:** `git rebase feat/ios-shell` this branch (couples desktop to unmerged iOS commits — acceptable since the desktop tasks below touch only `desktop/` and `web/js/{osc,constants}.js` + `web/index.html`, none of which the iOS work modifies).

**Coordination (do not break — see spec "Shared contracts"):** the hub WebSocket protocol (`compile-send`/`progress`/`done`/`error` on port 9000) and the project-JSON shape `compile.js` consumes are FROZEN and shared with the iOS session. This plan only *imports* `hub/src/*`; it must not modify those files or the protocol.

**Reused API surface (from `hub/src/`, do not reimplement):**
- `require('../hub/src/osc')` → `new OscSender({host, port, prefix})`, `.send(line) → Promise`, `.close()`
- `require('../hub/src/server')` → `startServer(config) → { wss, close() }`
- `require('../hub/src/config')` → `loadConfig(env) → config`
- `require('../hub/src/compile-bridge')` → `createCompiler`, `compileShow` (used internally by `startServer`)

---

## File Structure

- `desktop/package.json` — Electron app manifest + scripts + `electron-builder` config.
- `desktop/main.js` — Electron main process: window, OscSender for local sends, IPC handlers, embedded hub lifecycle.
- `desktop/preload.js` — `contextBridge` exposing `window.cuelist` (sendLine, settings, status events) to the renderer.
- `desktop/settings.js` — pure load/save/merge/validate of persisted settings (testable without Electron).
- `desktop/test/settings.test.js` — unit tests for `settings.js`.
- `web/js/transport.js` — **new** renderer module: transport selection (Electron-IPC vs WebSocket-proxy) + per-line send + status. Exposes `CC.transport`.
- `web/test/transport.test.js` — **new** jsdom-backed unit tests for the transport seam.
- `web/js/osc.js` — **modify**: route per-line send + connection/status through `CC.transport` instead of hard-wired WebSocket.
- `web/index.html` — **modify**: add `<script src="js/transport.js">` before `osc.js` in load order.
- `web/js/constants.js` — **no change** (`OSC_PROXY_URL`, `OSC_SEND_INTERVAL_MS` reused).

---

## Task 1: Electron scaffold that loads the web app

**Files:**
- Create: `desktop/package.json`
- Create: `desktop/main.js`
- Create: `desktop/preload.js`

- [ ] **Step 1: Create `desktop/package.json`**

```json
{
  "name": "cuelist-compiler-desktop",
  "version": "0.1.0",
  "private": true,
  "description": "Cross-platform desktop app: author cuelists and send OSC/UDP to grandMA3; embeds the hub for the iPhone companion.",
  "main": "main.js",
  "scripts": {
    "start": "electron .",
    "test": "node --test test",
    "dist": "electron-builder"
  },
  "devDependencies": {
    "electron": "^31.0.0",
    "electron-builder": "^24.13.3"
  },
  "dependencies": {
    "ws": "^8.18.0"
  }
}
```

- [ ] **Step 2: Create `desktop/preload.js` (empty bridge for now)**

```javascript
'use strict';
const { contextBridge } = require('electron');

// Expanded in Task 3. Presence of window.cuelist is how the renderer detects Electron.
contextBridge.exposeInMainWorld('cuelist', {
  isDesktop: true,
});
```

- [ ] **Step 3: Create `desktop/main.js` (minimal: load the web app)**

```javascript
'use strict';
const path = require('node:path');
const { app, BrowserWindow } = require('electron');

const WEB_INDEX = path.resolve(__dirname, '..', 'web', 'index.html');

function createWindow() {
  const win = new BrowserWindow({
    width: 1280,
    height: 860,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  win.loadFile(WEB_INDEX);
}

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
```

- [ ] **Step 4: Install and syntax-check**

Run: `cd desktop && npm install && node --check main.js && node --check preload.js`
Expected: install completes; both `node --check` print nothing (exit 0).

- [ ] **Step 5: Launch manually to confirm the app renders**

Run: `cd desktop && npm start`
Expected: an Electron window opens showing the Cuelist Compiler authoring UI (same as `web/index.html` in a browser). Close the window.

- [ ] **Step 6: Commit**

```bash
git add desktop/package.json desktop/main.js desktop/preload.js
git commit -m "feat(desktop): electron scaffold loading the web app"
```

---

## Task 2: Renderer transport seam (TDD)

Extract per-line send + connection/status into `web/js/transport.js` with two implementations selected at runtime. This is the only behavioral change to the renderer.

**Files:**
- Create: `web/js/transport.js`
- Create: `web/test/transport.test.js`

- [ ] **Step 1: Write the failing test**

`web/test/transport.test.js`:

```javascript
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Load transport.js into a sandbox with a fake window, return its CC.transport.
function loadTransport(win) {
  const code = fs.readFileSync(path.resolve(__dirname, '..', 'js', 'transport.js'), 'utf8');
  const sandbox = { window: win, WebSocket: win.WebSocket, console };
  sandbox.window.CC = sandbox.window.CC || {};
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: 'transport.js' });
  return sandbox.window.CC.transport;
}

test('selects Electron transport when window.cuelist is present', async () => {
  const sent = [];
  const win = { cuelist: { isDesktop: true, sendLine: (l) => { sent.push(l); return Promise.resolve(); } } };
  const t = loadTransport(win).make(win);
  assert.strictEqual(t.kind, 'electron');
  await t.connect();
  assert.strictEqual(t.status, 'online'); // main owns the socket → always online
  await t.sendLine('Clear');
  assert.deepStrictEqual(sent, ['Clear']);
});

test('selects WebSocket transport when window.cuelist is absent', () => {
  const win = { WebSocket: function () { this.readyState = 0; } };
  win.WebSocket.OPEN = 1; win.WebSocket.CONNECTING = 0;
  const t = loadTransport(win).make(win, { proxyUrl: 'ws://127.0.0.1:8765' });
  assert.strictEqual(t.kind, 'websocket');
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd web && node --test test/transport.test.js`
Expected: FAIL — `transport.js` does not exist / `CC.transport` undefined.

- [ ] **Step 3: Implement `web/js/transport.js`**

```javascript
// transport.js — selects how per-line OSC commands leave the app.
// Electron: over IPC to the main process (native UDP). Browser: WebSocket to proxy.
// Exposes CC.transport.make(win, opts). Depends on: nothing (constants passed in).

(function () {
  function makeElectron(win) {
    const t = {
      kind: 'electron',
      status: 'offline',
      onStatus: null,
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
      _set(s) { this.status = s; if (this.onStatus) this.onStatus(s); },
      connect() {
        return new Promise((resolve) => {
          this._set('connecting');
          ws = new win.WebSocket(url);
          ws.addEventListener('open', () => { this._set('online'); resolve(); });
          ws.addEventListener('close', () => { this._set('offline'); });
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd web && node --test test/transport.test.js`
Expected: PASS (2 tests).

- [ ] **Step 5: Wire `osc.js` to use the transport**

In `web/js/osc.js`, replace the direct-WebSocket internals. Make these exact edits:

Replace the module-level state block:
```javascript
let oscWs = null;
let oscState = 'offline'; // offline | connecting | online | sending
let oscReconnectTimer = null;
let oscSending = false;
```
with:
```javascript
let transport = null;
let oscState = 'offline'; // offline | connecting | online | sending
let oscReconnectTimer = null;
let oscSending = false;
```

Replace the whole `oscConnect()` function with:
```javascript
function oscConnect() {
  if (!transport) {
    transport = CC.transport.make(window, { proxyUrl: OSC_PROXY_URL });
    transport.onStatus = (s) => {
      if (oscSending) return;            // don't clobber the sending label
      if (s === 'online') { setOscState('online'); if (oscReconnectTimer) { clearTimeout(oscReconnectTimer); oscReconnectTimer = null; } }
      else if (s === 'connecting') setOscState('connecting');
      else { setOscState('offline'); if (!oscReconnectTimer) oscReconnectTimer = setTimeout(() => { oscReconnectTimer = null; oscConnect(); }, 3000); }
    };
  }
  if (oscState === 'online' || oscState === 'connecting') return;
  transport.connect().catch(() => setOscState('offline'));
}
```

Replace `oscSendLine` with a delegation:
```javascript
function oscSendLine(line) {
  if (!transport) return Promise.reject(new Error('OSC offline'));
  return transport.sendLine(line);
}
```

Leave `setOscState`, `sendCmdLinesViaOsc`, `sendCurrentViaOsc`, `sendAllViaOsc`, and the `CC.osc` export unchanged — they call `oscSendLine`/`oscConnect`, which now route through the transport.

- [ ] **Step 6: Add `transport.js` to the page load order**

In `web/index.html`, add the script tag immediately BEFORE the `osc.js` tag:
```html
    <script src="js/transport.js"></script>
```
(Order must be `…compile.js → audio.js → transport.js → osc.js → render.js → main.js`.)

- [ ] **Step 7: Verify the app still loads (browser-mode regression)**

Run: `cd web && node --test test/transport.test.js`
Expected: PASS. Then open `web/index.html` in Chrome with the proxy running (`cd proxy && ./start.sh`) — the OSC pill should still connect/show "OSC online" exactly as before (browser transport unchanged in behavior).

- [ ] **Step 8: Commit**

```bash
git add web/js/transport.js web/test/transport.test.js web/js/osc.js web/index.html
git commit -m "feat(web): transport seam for Electron vs WebSocket-proxy send"
```

---

## Task 3: Main-process UDP sender, settings, and preload bridge

**Files:**
- Create: `desktop/settings.js`
- Create: `desktop/test/settings.test.js`
- Modify: `desktop/main.js`
- Modify: `desktop/preload.js`

- [ ] **Step 1: Write the failing settings test**

`desktop/test/settings.test.js`:

```javascript
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const { defaults, merge, validate } = require('../settings');

test('defaults match hub expectations', () => {
  const d = defaults();
  assert.strictEqual(d.ma3Host, '127.0.0.1');
  assert.strictEqual(d.ma3Port, 8000);
  assert.strictEqual(d.ma3Prefix, 'gma3');
  assert.strictEqual(d.hubEnabled, true);
  assert.strictEqual(d.hubPort, 9000);
  assert.strictEqual(d.intervalMs, 20);
});

test('merge overlays partial user settings onto defaults', () => {
  const m = merge(defaults(), { ma3Host: '10.0.0.2', hubPort: 9100 });
  assert.strictEqual(m.ma3Host, '10.0.0.2');
  assert.strictEqual(m.hubPort, 9100);
  assert.strictEqual(m.ma3Port, 8000); // untouched
});

test('validate rejects out-of-range ports', () => {
  assert.throws(() => validate(merge(defaults(), { ma3Port: 70000 })), /ma3Port/);
  assert.throws(() => validate(merge(defaults(), { hubPort: 0 })), /hubPort/);
});

test('validate accepts a sane config', () => {
  assert.doesNotThrow(() => validate(defaults()));
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd desktop && node --test test/settings.test.js`
Expected: FAIL — cannot find module `../settings`.

- [ ] **Step 3: Implement `desktop/settings.js`**

```javascript
'use strict';
const fs = require('node:fs');
const path = require('node:path');

function defaults() {
  return {
    ma3Host: '127.0.0.1',
    ma3Port: 8000,
    ma3Prefix: 'gma3',
    intervalMs: 20,
    hubEnabled: true,
    hubPort: 9000,
  };
}

function merge(base, partial) {
  return Object.assign({}, base, partial || {});
}

function validate(s) {
  const port = (name, v) => {
    if (!Number.isInteger(v) || v < 1 || v > 65535) throw new Error(`invalid ${name}: ${v}`);
  };
  port('ma3Port', s.ma3Port);
  port('hubPort', s.hubPort);
  if (!s.ma3Host) throw new Error('invalid ma3Host');
  if (!s.ma3Prefix) throw new Error('invalid ma3Prefix');
  if (!Number.isInteger(s.intervalMs) || s.intervalMs < 0) throw new Error('invalid intervalMs');
  return s;
}

// Electron-only persistence helpers (not exercised by unit tests).
function filePath(userDataDir) { return path.join(userDataDir, 'settings.json'); }

function load(userDataDir) {
  try {
    const raw = fs.readFileSync(filePath(userDataDir), 'utf8');
    return validate(merge(defaults(), JSON.parse(raw)));
  } catch { return defaults(); }
}

function save(userDataDir, s) {
  const v = validate(merge(defaults(), s));
  fs.writeFileSync(filePath(userDataDir), JSON.stringify(v, null, 2));
  return v;
}

module.exports = { defaults, merge, validate, load, save, filePath };
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd desktop && node --test test/settings.test.js`
Expected: PASS (4 tests).

- [ ] **Step 5: Expand `desktop/preload.js` to expose the bridge**

```javascript
'use strict';
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('cuelist', {
  isDesktop: true,
  sendLine: (line) => ipcRenderer.invoke('cuelist:sendLine', line),
  getSettings: () => ipcRenderer.invoke('cuelist:getSettings'),
  setSettings: (partial) => ipcRenderer.invoke('cuelist:setSettings', partial),
  getStatus: () => ipcRenderer.invoke('cuelist:getStatus'),
  onStatus: (cb) => {
    const handler = (_e, status) => cb(status);
    ipcRenderer.on('cuelist:status', handler);
    return () => ipcRenderer.removeListener('cuelist:status', handler);
  },
});
```

- [ ] **Step 6: Wire the OscSender + IPC handlers in `desktop/main.js`**

Add near the top (after the existing requires):
```javascript
const settingsModule = require('./settings');
const { OscSender } = require('../hub/src/osc');
const { ipcMain } = require('electron');

let settings = settingsModule.defaults();
let sender = null;

function rebuildSender() {
  if (sender) sender.close();
  sender = new OscSender({ host: settings.ma3Host, port: settings.ma3Port, prefix: settings.ma3Prefix });
}
```

Inside `app.whenReady().then(...)`, BEFORE `createWindow()`, add:
```javascript
  settings = settingsModule.load(app.getPath('userData'));
  rebuildSender();

  ipcMain.handle('cuelist:sendLine', async (_e, line) => { await sender.send(line); return true; });
  ipcMain.handle('cuelist:getSettings', () => settings);
  ipcMain.handle('cuelist:setSettings', (_e, partial) => {
    settings = settingsModule.save(app.getPath('userData'), settingsModule.merge(settings, partial));
    rebuildSender();
    return settings;
  });
```

Add cleanup at the bottom:
```javascript
app.on('before-quit', () => { if (sender) sender.close(); });
```

- [ ] **Step 7: Syntax-check and manual smoke**

Run: `cd desktop && node --check main.js && node --check preload.js && npm start`
Expected: app launches; in the renderer the OSC pill shows "OSC online" (Electron transport reports online immediately). Sending with no desk present will not error the UI (UDP is fire-and-forget); a real send is verified in Task 7.

- [ ] **Step 8: Commit**

```bash
git add desktop/settings.js desktop/test/settings.test.js desktop/main.js desktop/preload.js
git commit -m "feat(desktop): native UDP send + persisted settings over IPC"
```

---

## Task 4: Embed the hub server for the iPhone companion

**Files:**
- Modify: `desktop/main.js`

- [ ] **Step 1: Start the embedded hub in `desktop/main.js`**

Add to the requires:
```javascript
const { startServer } = require('../hub/src/server');
```

Add module-level state:
```javascript
let hub = null;
function hubConfig() {
  return {
    host: '0.0.0.0',
    port: settings.hubPort,
    ma3Host: settings.ma3Host,
    ma3Port: settings.ma3Port,
    ma3Prefix: settings.ma3Prefix,
    intervalMs: settings.intervalMs,
    webJsDir: undefined, // hub/src/compile-bridge defaults to ../../web/js (correct on this layout)
  };
}
function startHub() {
  if (hub) return;
  if (!settings.hubEnabled) return;
  hub = startServer(hubConfig());
}
function stopHub() {
  if (!hub) return;
  const h = hub; hub = null;
  return h.close();
}
```

Inside `app.whenReady().then(...)` after the IPC handlers, add:
```javascript
  startHub();
```

Make `cuelist:setSettings` restart the hub when its config changes — replace the handler body with:
```javascript
  ipcMain.handle('cuelist:setSettings', async (_e, partial) => {
    settings = settingsModule.save(app.getPath('userData'), settingsModule.merge(settings, partial));
    rebuildSender();
    await stopHub();
    startHub();
    return settings;
  });
```

Add to `before-quit`:
```javascript
app.on('before-quit', () => { if (sender) sender.close(); stopHub(); });
```

- [ ] **Step 2: Add a `getStatus` IPC handler reporting phone connection**

Add this handler next to the others inside `app.whenReady()`:
```javascript
  ipcMain.handle('cuelist:getStatus', () => ({
    oscTarget: `${settings.ma3Host}:${settings.ma3Port} /${settings.ma3Prefix}/cmd`,
    hubEnabled: settings.hubEnabled,
    hubPort: settings.hubPort,
    phoneConnected: !!(hub && hub.wss && hub.wss.clients.size > 0),
  }));
```

- [ ] **Step 3: Verify hub tests still pass (unchanged contract)**

Run: `cd hub && npm install && npm test`
Expected: PASS — all existing hub tests green (12 tests). This confirms the imported server is intact.

- [ ] **Step 4: Manual smoke — phone protocol against the embedded hub**

Run: `cd desktop && npm start`, then in another terminal run the hub's own golden client check against `ws://127.0.0.1:9000` (reuse `hub/tools/gen-golden.js` or a `wscat` sending `{"type":"ping"}` → expect `{"type":"pong"}`).
Expected: `pong` received → the embedded hub is live on 9000.

- [ ] **Step 5: Commit**

```bash
git add desktop/main.js
git commit -m "feat(desktop): embed hub server on :9000 — replaces the Pi for iPhone"
```

---

## Task 5: Settings + status UI in the renderer

**Files:**
- Modify: `web/index.html`
- Modify: `web/js/osc.js`

- [ ] **Step 1: Add a settings panel + status row to `web/index.html`**

Add this block adjacent to the existing OSC pill markup (find `id="oscPill"`):
```html
<div id="deskStatusRow" class="desk-status" hidden>
  <span id="oscTargetLabel">OSC → —</span>
  <span id="phonePill" class="phone-pill">📱 no phone</span>
  <button id="openSettingsBtn" type="button">⚙ Settings</button>
</div>
<dialog id="settingsDialog">
  <form method="dialog" id="settingsForm">
    <label>MA3 host <input id="setMa3Host" type="text"></label>
    <label>MA3 UDP port <input id="setMa3Port" type="number" min="1" max="65535"></label>
    <label>OSC prefix <input id="setMa3Prefix" type="text"></label>
    <label>Throttle ms <input id="setIntervalMs" type="number" min="0"></label>
    <label>Embedded hub (iPhone) <input id="setHubEnabled" type="checkbox"></label>
    <label>Hub port <input id="setHubPort" type="number" min="1" max="65535"></label>
    <menu><button value="cancel">Cancel</button><button id="saveSettingsBtn" value="ok">Save</button></menu>
  </form>
</dialog>
```

- [ ] **Step 2: Add the settings/status controller to `web/js/osc.js`**

Append before the `// --- public surface` line:
```javascript
// --- Desktop settings + status (Electron only) -----------------------------
function initDesktopChrome() {
  if (!(window.cuelist && window.cuelist.isDesktop)) return; // browser: no native settings
  const row = document.getElementById('deskStatusRow');
  if (row) row.hidden = false;

  async function refreshStatus() {
    const st = await window.cuelist.getStatus();
    const tl = document.getElementById('oscTargetLabel');
    if (tl) tl.textContent = 'OSC → ' + st.oscTarget;
    const pp = document.getElementById('phonePill');
    if (pp) { pp.textContent = st.phoneConnected ? '📱 phone connected' : '📱 no phone'; pp.classList.toggle('connected', st.phoneConnected); }
  }
  refreshStatus();
  setInterval(refreshStatus, 2000);

  const dlg = document.getElementById('settingsDialog');
  document.getElementById('openSettingsBtn').addEventListener('click', async () => {
    const s = await window.cuelist.getSettings();
    document.getElementById('setMa3Host').value = s.ma3Host;
    document.getElementById('setMa3Port').value = s.ma3Port;
    document.getElementById('setMa3Prefix').value = s.ma3Prefix;
    document.getElementById('setIntervalMs').value = s.intervalMs;
    document.getElementById('setHubEnabled').checked = s.hubEnabled;
    document.getElementById('setHubPort').value = s.hubPort;
    dlg.showModal();
  });
  document.getElementById('settingsForm').addEventListener('submit', async (ev) => {
    if (ev.submitter && ev.submitter.value === 'cancel') return;
    await window.cuelist.setSettings({
      ma3Host: document.getElementById('setMa3Host').value.trim(),
      ma3Port: parseInt(document.getElementById('setMa3Port').value, 10),
      ma3Prefix: document.getElementById('setMa3Prefix').value.trim(),
      intervalMs: parseInt(document.getElementById('setIntervalMs').value, 10),
      hubEnabled: document.getElementById('setHubEnabled').checked,
      hubPort: parseInt(document.getElementById('setHubPort').value, 10),
    });
    refreshStatus();
  });
}
```

Add `initDesktopChrome` to the `CC.osc` export object, and call it from `web/js/main.js` near the existing `oscConnect();` call:
```javascript
CC.osc.initDesktopChrome && CC.osc.initDesktopChrome();
```

- [ ] **Step 3: Verify browser regression (panel stays hidden)**

Run: open `web/index.html` in Chrome.
Expected: no settings row visible (it's `hidden` and `initDesktopChrome` early-returns without `window.cuelist`); existing OSC pill behavior unchanged.

- [ ] **Step 4: Verify in Electron**

Run: `cd desktop && npm start`
Expected: the status row is visible, shows `OSC → 127.0.0.1:8000 /gma3/cmd`; ⚙ Settings opens the dialog; changing MA3 host + Save updates the target label.

- [ ] **Step 5: Commit**

```bash
git add web/index.html web/js/osc.js web/js/main.js
git commit -m "feat(desktop): settings dialog + OSC target / phone-connected status"
```

---

## Task 6: Cross-platform packaging with electron-builder

**Files:**
- Modify: `desktop/package.json`

- [ ] **Step 1: Add the `build` config to `desktop/package.json`**

Add this top-level key:
```json
  "build": {
    "appId": "com.blearred.cuelistcompiler",
    "productName": "Cuelist Compiler",
    "files": ["main.js", "preload.js", "settings.js", "../web/**/*", "../hub/src/**/*", "node_modules/**/*"],
    "mac": {
      "target": "dmg",
      "category": "public.app-category.music",
      "hardenedRuntime": true,
      "gatekeeperAssess": false,
      "entitlements": "build/entitlements.mac.plist",
      "entitlementsInherit": "build/entitlements.mac.plist"
    },
    "win": {
      "target": "nsis"
    }
  }
```

- [ ] **Step 2: Create `desktop/build/entitlements.mac.plist` (network + JIT for Electron)**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.network.server</key><true/>
</dict>
</plist>
```

- [ ] **Step 3: Build the macOS DMG (signed + notarized)**

Set notarization env (Apple team `UWJSLFQDGL`):
```bash
export APPLE_TEAM_ID=UWJSLFQDGL
export APPLE_ID=<apple-id-email>
export APPLE_APP_SPECIFIC_PASSWORD=<app-specific-pw>
cd desktop && npm run dist
```
Expected: `desktop/dist/Cuelist Compiler-0.1.0.dmg` produced, signed + notarized (no Gatekeeper warning on open).

- [ ] **Step 4: Build the Windows installer (unsigned for v1)**

On a Windows machine (or CI runner): `cd desktop && npm run dist`
Expected: `desktop/dist/Cuelist Compiler Setup 0.1.0.exe`. Note: launching shows a SmartScreen "unknown publisher" warning (clickable through) — documented v1 limitation; a Windows code-signing cert is deferred.

- [ ] **Step 5: Commit**

```bash
git add desktop/package.json desktop/build/entitlements.mac.plist
git commit -m "build(desktop): electron-builder config for macOS (signed) + Windows (unsigned)"
```

---

## Task 7: On-hardware smoke (manual checklist)

No code. Run these and check each box. This mirrors the Pi hardware smoke already performed.

- [ ] **Step 1: onPC loopback send.** Start MA3 onPC with OSC input UDP 8000, prefix `gma3`, **Echo Input = Yes**. Launch the desktop app (default settings `127.0.0.1:8000`). Author a one-cue song → **Send current → MA**. Expected: the command dispatches on onPC.

- [ ] **Step 2: Real desk over cat5.** Connect the laptop to the desk via the USB-Ethernet adapter (laptop static `10.0.0.10/24`, desk `10.0.0.2`). In ⚙ Settings set MA3 host `10.0.0.2`, Save. Send the `examples/SONG_1` show → **Send all → MA**. Expected: the sequence builds on the desk (same result as the Pi smoke: Sequence 666, Cue 0.1 + Cue 1).

- [ ] **Step 3: iPhone over the Mac hotspot.** Enable macOS Internet Sharing (share from Ethernet → WiFi). Join the iPhone to the Mac's WiFi. In the iPhone app set hub host to the Mac's AP IP (`~192.168.2.1`), port 9000. Send a show from the phone. Expected: `📱 phone connected` shows in the desktop status row; the desk receives the cues; the phone sees `progress`/`done`. **Pi is now fully unnecessary.**

- [ ] **Step 4: Update docs.** In `README.md`, document the desktop app as the recommended path for operators and mark the Pi (`hub/deploy/cuelist-hub.service`) as superseded. Commit:
```bash
git add README.md
git commit -m "docs: desktop app is the recommended operator path; Pi superseded"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** Topology → T1+T4; transport abstraction → T2; native UDP → T3; embedded hub/Pi deletion → T4 (+ T7.4 doc); settings & status → T3+T5; networking/hotspot → T7.3; error handling → reuses hub contract (T4) + UDP fire-and-forget noted (T3.7); testing → T2/T3/T4 unit + T7 smoke; distribution/signing → T6; YAGNI deferrals (auto-update, mDNS, sync) → not in plan by design. Open spec items (keep `proxy/`; Windows unsigned) → both honored (proxy untouched/kept; T6.4 unsigned).
- **Placeholder scan:** none — every code/edit step shows real content; `<apple-id-email>`/`<app-specific-pw>` are user-supplied secrets, not code placeholders.
- **Type consistency:** `CC.transport.make(win, opts)` defined T2 used T2.5; `window.cuelist.{sendLine,getSettings,setSettings,getStatus,onStatus,isDesktop}` defined in preload T3.5 used in T2.3/T5.2; settings keys (`ma3Host/ma3Port/ma3Prefix/intervalMs/hubEnabled/hubPort`) consistent across T3/T4/T5; `OscSender`/`startServer` signatures match `hub/src`.
