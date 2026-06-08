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
  // Audio file foundation (native dialog + fs).
  // pickAudio → { path, name } | null (user cancelled)
  // readAudio(path) → { buffer, name } | { error }
  // pathExists(path) → boolean
  pickAudio: () => ipcRenderer.invoke('cuelist:pickAudio'),
  readAudio: (filePath) => ipcRenderer.invoke('cuelist:readAudio', filePath),
  pathExists: (filePath) => ipcRenderer.invoke('cuelist:pathExists', filePath),
  // Project file IO.
  // openProject() → { path, content } | null (cancelled) | { error }
  // saveProjectAs(content, suggestedName) → { path } | null | { error }
  // saveProjectAt(filePath, content) → { ok } | { error }
  // pickBundleDir(suggestedName) → { jsonPath, assetsDir, baseName } | null | { error }
  // copyAudioToAssets(srcPath, assetsDir, dstName) → { dstPath } | { error }
  openProject: () => ipcRenderer.invoke('cuelist:openProject'),
  saveProjectAs: (content, suggestedName) => ipcRenderer.invoke('cuelist:saveProjectAs', content, suggestedName),
  saveProjectAt: (filePath, content) => ipcRenderer.invoke('cuelist:saveProjectAt', filePath, content),
  pickBundleDir: (suggestedName) => ipcRenderer.invoke('cuelist:pickBundleDir', suggestedName),
  copyAudioToAssets: (srcPath, assetsDir, dstName) => ipcRenderer.invoke('cuelist:copyAudioToAssets', srcPath, assetsDir, dstName),
  // Path math (uses node:path semantics — correct on Windows).
  resolvePath: (...parts) => ipcRenderer.invoke('cuelist:resolvePath', parts),
  relativePath: (from, to) => ipcRenderer.invoke('cuelist:relativePath', from, to),
  isAbsolutePath: (p) => ipcRenderer.invoke('cuelist:isAbsolutePath', p),
});
