'use strict';
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('hub', {
  getState: () => ipcRenderer.invoke('hub:getState'),
  getSettings: () => ipcRenderer.invoke('hub:getSettings'),
  setSettings: (partial) => ipcRenderer.invoke('hub:setSettings', partial),
  regenCode: () => ipcRenderer.invoke('hub:regenCode'),
  // push channels: main → renderer
  onState: (cb) => ipcRenderer.on('hub:state', (_e, s) => cb(s)),
  onPeer: (cb) => ipcRenderer.on('hub:peer', (_e, b) => cb(b)),
  onLog: (cb) => ipcRenderer.on('hub:log', (_e, entry) => cb(entry)),
});
