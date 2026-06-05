'use strict';
const path = require('node:path');
const { app, BrowserWindow, ipcMain } = require('electron');
const settingsModule = require('./settings');
const { OscSender } = require('../hub/src/osc');

const WEB_INDEX = path.resolve(__dirname, '..', 'web', 'index.html');

let settings = settingsModule.defaults();
let sender = null;

function rebuildSender() {
  if (sender) sender.close();
  sender = new OscSender({ host: settings.ma3Host, port: settings.ma3Port, prefix: settings.ma3Prefix });
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
  ipcMain.handle('cuelist:setSettings', (_e, partial) => {
    settings = settingsModule.save(app.getPath('userData'), settingsModule.merge(settings, partial));
    rebuildSender();
    return settings;
  });

  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('before-quit', () => { if (sender) sender.close(); });
