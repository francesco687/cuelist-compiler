'use strict';
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('hub', {
  getState: () => ipcRenderer.invoke('hub:getState'),
  getSettings: () => ipcRenderer.invoke('hub:getSettings'),
  setSettings: (partial) => ipcRenderer.invoke('hub:setSettings', partial),
  regenCode: () => ipcRenderer.invoke('hub:regenCode'),
  kickAll: () => ipcRenderer.invoke('hub:kickAll'),
  // push channels: main → renderer
  onState: (cb) => ipcRenderer.on('hub:state', (_e, s) => cb(s)),
  onRoster: (cb) => ipcRenderer.on('hub:roster', (_e, phones) => cb(phones)),
  onLog: (cb) => ipcRenderer.on('hub:log', (_e, entry) => cb(entry)),
});
