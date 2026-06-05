'use strict';
const { contextBridge, ipcRenderer } = require('electron');

// Presence of window.cuelist is how the renderer detects Electron.
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
