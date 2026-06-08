'use strict';
const path = require('node:path');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const { app, BrowserWindow, ipcMain, dialog } = require('electron');
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
  // The WebSocketServer emits 'error' asynchronously (e.g. EADDRINUSE when port 9000 is
  // already held by a leftover hub or a second app instance). With no listener Node throws
  // on the unhandled 'error' event and the whole Electron process hard-crashes at boot.
  // Register the handler synchronously (same tick) so it's in place before that fires.
  hub.wss.on('error', (err) => {
    console.error('[hub] server error:', err && err.message ? err.message : err);
    // Fail soft: the desktop OSC path still works; only the iPhone companion is unavailable.
    // Null hub first so getStatus() reports phoneConnected:false and the `if (hub) return`
    // guard won't be stuck on a dead hub — a later setSettings/restart can retry cleanly.
    const h = hub; hub = null;
    // close() resolves via wss.close(resolve), but its Promise executor runs synchronous
    // teardown (clients.terminate / sender.close) that can throw on a never-bound server,
    // which would reject the Promise. Swallow it to avoid an unhandledRejection.
    Promise.resolve(h.close()).catch(() => { /* already tearing down */ });
  });
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
    // Deliberate tradeoff: restarting the hub on every save briefly drops the phone connection,
    // and a phone message arriving in that window hits a closing sender and gets a caught
    // {type:'error'} (graceful, not a crash). Settings saves are rare, deliberate actions and
    // the phone reconnects within its retry cycle, so the simplicity is worth it.
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

  // Audio file foundation. Renderer cannot read disk directly under contextIsolation,
  // and File.path was removed from the Web API in recent Electron. Audio picking and
  // reading therefore round-trips through the main process.
  ipcMain.handle('cuelist:pickAudio', async () => {
    const win = BrowserWindow.getFocusedWindow();
    const res = await dialog.showOpenDialog(win, {
      title: 'Pick audio file',
      properties: ['openFile'],
      filters: [
        { name: 'Audio', extensions: ['mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg', 'opus'] },
        { name: 'All files', extensions: ['*'] },
      ],
    });
    if (res.canceled || !res.filePaths || res.filePaths.length === 0) return null;
    const p = res.filePaths[0];
    return { path: p, name: path.basename(p) };
  });

  ipcMain.handle('cuelist:readAudio', async (_e, filePath) => {
    if (typeof filePath !== 'string' || !filePath) return { error: 'invalid path' };
    try {
      const buf = await fsp.readFile(filePath);
      // Send the underlying ArrayBuffer (electron handles structured clone of typed arrays).
      const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
      return { buffer: ab, name: path.basename(filePath) };
    } catch (e) {
      return { error: (e && e.message) || 'read failed' };
    }
  });

  ipcMain.handle('cuelist:pathExists', async (_e, filePath) => {
    if (typeof filePath !== 'string' || !filePath) return false;
    try { await fsp.access(filePath, fs.constants.R_OK); return true; }
    catch { return false; }
  });

  ipcMain.handle('cuelist:openProject', async () => {
    const win = BrowserWindow.getFocusedWindow();
    const res = await dialog.showOpenDialog(win, {
      title: 'Open project',
      properties: ['openFile'],
      filters: [{ name: 'Cuelist project', extensions: ['json'] }, { name: 'All files', extensions: ['*'] }],
    });
    if (res.canceled || !res.filePaths || res.filePaths.length === 0) return null;
    const p = res.filePaths[0];
    try {
      const content = await fsp.readFile(p, 'utf8');
      return { path: p, content };
    } catch (e) {
      return { error: (e && e.message) || 'read failed' };
    }
  });

  ipcMain.handle('cuelist:saveProjectAs', async (_e, content, suggestedName) => {
    const win = BrowserWindow.getFocusedWindow();
    const res = await dialog.showSaveDialog(win, {
      title: 'Save project',
      defaultPath: typeof suggestedName === 'string' && suggestedName ? suggestedName : 'show.json',
      filters: [{ name: 'Cuelist project', extensions: ['json'] }],
    });
    if (res.canceled || !res.filePath) return null;
    try {
      await fsp.writeFile(res.filePath, content, 'utf8');
      return { path: res.filePath };
    } catch (e) {
      return { error: (e && e.message) || 'write failed' };
    }
  });

  ipcMain.handle('cuelist:saveProjectAt', async (_e, filePath, content) => {
    if (typeof filePath !== 'string' || !filePath) return { error: 'invalid path' };
    try {
      await fsp.writeFile(filePath, content, 'utf8');
      return { ok: true };
    } catch (e) {
      return { error: (e && e.message) || 'write failed' };
    }
  });

  // Save-as-bundle: pick a destination .json; create a sibling <basename>_assets/ dir.
  ipcMain.handle('cuelist:pickBundleDir', async (_e, suggestedName) => {
    const win = BrowserWindow.getFocusedWindow();
    const res = await dialog.showSaveDialog(win, {
      title: 'Save project + assets',
      defaultPath: typeof suggestedName === 'string' && suggestedName ? suggestedName : 'show.json',
      filters: [{ name: 'Cuelist project', extensions: ['json'] }],
    });
    if (res.canceled || !res.filePath) return null;
    const jsonPath = res.filePath;
    const dir = path.dirname(jsonPath);
    const baseName = path.basename(jsonPath, path.extname(jsonPath));
    const assetsDir = path.join(dir, baseName + '_assets');
    try {
      await fsp.mkdir(assetsDir, { recursive: true });
      return { jsonPath, assetsDir, baseName };
    } catch (e) {
      return { error: (e && e.message) || 'mkdir failed' };
    }
  });

  ipcMain.handle('cuelist:copyAudioToAssets', async (_e, srcPath, assetsDir, dstName) => {
    if (!srcPath || !assetsDir || !dstName) return { error: 'invalid args' };
    const dstPath = path.join(assetsDir, dstName);
    try {
      await fsp.copyFile(srcPath, dstPath);
      return { dstPath };
    } catch (e) {
      return { error: (e && e.message) || 'copy failed' };
    }
  });

  ipcMain.handle('cuelist:resolvePath', (_e, parts) => path.resolve(...(Array.isArray(parts) ? parts : [parts])));
  ipcMain.handle('cuelist:relativePath', (_e, from, to) => path.relative(from, to));
  ipcMain.handle('cuelist:isAbsolutePath', (_e, p) => typeof p === 'string' && path.isAbsolute(p));

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
