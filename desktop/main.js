'use strict';
const path = require('node:path');
const { app, BrowserWindow, ipcMain } = require('electron');
const settingsModule = require('./settings');
const { OscSender } = require('../hub/src/osc');
const { startServer } = require('../hub/src/server');

const WEB_INDEX = path.resolve(__dirname, '..', 'web', 'index.html');

let settings = settingsModule.defaults();
let sender = null;
let hub = null;

function rebuildSender() {
  if (sender) sender.close();
  sender = new OscSender({ host: settings.ma3Host, port: settings.ma3Port, prefix: settings.ma3Prefix });
}

function hubConfig() {
  return {
    host: '0.0.0.0',
    port: settings.hubPort,
    ma3Host: settings.ma3Host,
    ma3Port: settings.ma3Port,
    ma3Prefix: settings.ma3Prefix,
    intervalMs: settings.intervalMs,
    webJsDir: undefined, // compile-bridge defaults to ../../web/js relative to hub/src — correct on this layout
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
  settings = settingsModule.load(app.getPath('userData'));
  rebuildSender();

  ipcMain.handle('cuelist:sendLine', async (_e, line) => { await sender.send(line); return true; });
  ipcMain.handle('cuelist:getSettings', () => settings);
  ipcMain.handle('cuelist:setSettings', async (_e, partial) => {
    settings = settingsModule.save(app.getPath('userData'), settingsModule.merge(settings, partial));
    rebuildSender();
    await stopHub();
    startHub();
    return settings;
  });
  ipcMain.handle('cuelist:getStatus', () => ({
    oscTarget: `${settings.ma3Host}:${settings.ma3Port} /${settings.ma3Prefix}/cmd`,
    hubEnabled: settings.hubEnabled,
    hubPort: settings.hubPort,
    phoneConnected: !!(hub && hub.wss && hub.wss.clients.size > 0),
  }));

  startHub();

  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('before-quit', () => { if (sender) sender.close(); stopHub(); });
