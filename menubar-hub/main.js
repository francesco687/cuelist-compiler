'use strict';
const path = require('node:path');
const { app, Tray, Menu, BrowserWindow, ipcMain, nativeImage, screen } = require('electron');
const settingsModule = require('./src/settings');
const { RelayHubClient } = require('./src/relay-client');

let tray = null;
let popover = null;
let client = null;
let settings = settingsModule.defaults();
let state = { relay: 'offline', peer: false };

// In a packaged build the hub core and web compiler don't sit at their dev-time
// relative paths — electron-builder ships them under Resources (see extraResources).
// Inject the core and point the compiler at the bundled web/js. In dev both are
// undefined, so relay-client falls back to its own sibling-repo requires.
function hubCore() {
  return app.isPackaged
    ? require(path.join(process.resourcesPath, 'hub', 'src', 'handle'))
    : undefined;
}
function packagedWebJsDir() {
  return app.isPackaged ? path.join(process.resourcesPath, 'web', 'js') : undefined;
}

function buildClient() {
  if (client) client.close();
  state = { relay: 'connecting', peer: false, roster: [] };
  // webJsDir is injected per-run (not persisted) so settings.json stays portable.
  const runtimeConfig = { ...settings, webJsDir: packagedWebJsDir() };
  client = new RelayHubClient(runtimeConfig, {
    onState: (s) => { state.relay = s; pushToRenderer('hub:state', s); updateTrayTitle(); },
    onRoster: (phones) => {
      state.roster = phones; state.peer = phones.length > 0;
      pushToRenderer('hub:roster', phones); updateTrayTitle();
    },
    onLog:   (e) => pushToRenderer('hub:log', e),
  }, { core: hubCore() });
  client.connect();
}

function pushToRenderer(channel, payload) {
  if (popover && !popover.isDestroyed()) popover.webContents.send(channel, payload);
}

function updateTrayTitle() {
  if (!tray) return;
  // Menubar glyph: ● paired, ◐ relay-up-no-phone, ○ offline.
  const glyph = state.peer ? '●' : state.relay === 'online' ? '◐' : '○';
  tray.setTitle(` ${glyph}`);
}

function createPopover() {
  popover = new BrowserWindow({
    width: 360, height: 480, show: false, frame: false, resizable: false,
    fullscreenable: false, skipTaskbar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false },
  });
  popover.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  popover.on('blur', () => { if (popover && !popover.isDestroyed()) popover.hide(); });
}

function quitApp() {
  // Real teardown: before-quit closes the relay client; app.quit() overrides the
  // window-all-closed keep-alive so the menubar process actually exits.
  app.quit();
}

function showTrayMenu() {
  const menu = Menu.buildFromTemplate([
    { label: 'Quit Saetta Hub', accelerator: 'Command+Q', click: quitApp },
  ]);
  tray.popUpContextMenu(menu);
}

function togglePopover() {
  if (!popover) return;
  if (popover.isVisible()) { popover.hide(); return; }
  const tb = tray.getBounds();
  const wb = popover.getBounds();
  const x = Math.round(tb.x + tb.width / 2 - wb.width / 2);
  const y = Math.round(tb.y + tb.height);
  popover.setPosition(x, Math.max(y, 0), false);
  popover.show();
  popover.focus();
}

function trayIcon() {
  // Template image so macOS tints it for light/dark menubars. A 16x16 transparent
  // PNG ships at renderer/trayTemplate.png; fall back to an empty image if missing.
  const p = path.join(__dirname, 'renderer', 'trayTemplate.png');
  const img = nativeImage.createFromPath(p);
  img.setTemplateImage(true);
  return img.isEmpty() ? nativeImage.createEmpty() : img;
}

app.whenReady().then(() => {
  if (app.dock) app.dock.hide();                 // menubar-only, no dock icon
  settings = settingsModule.loadOrInit(app.getPath('userData'));

  tray = new Tray(trayIcon());
  tray.setToolTip('Saetta Hub');
  tray.on('click', togglePopover);
  tray.on('right-click', showTrayMenu);          // right-click → Quit (left-click stays popover)
  updateTrayTitle();

  createPopover();
  buildClient();

  ipcMain.handle('hub:getState', () => ({ ...state, pairingCode: settings.pairingCode }));
  ipcMain.handle('hub:getSettings', () => settings);
  ipcMain.handle('hub:setSettings', (_e, partial) => {
    settings = settingsModule.save(app.getPath('userData'), settingsModule.merge(settings, partial));
    buildClient();                                // reconnect with the new config
    return settings;
  });
  ipcMain.handle('hub:regenCode', () => {
    settings = settingsModule.save(app.getPath('userData'),
      settingsModule.merge(settings, { pairingCode: settingsModule.generatePairingCode() }));
    buildClient();
    return settings.pairingCode;
  });
});

app.on('window-all-closed', (e) => { e.preventDefault(); /* stay alive in the menubar */ });
app.on('before-quit', () => { if (client) client.close(); });
