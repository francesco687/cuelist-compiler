'use strict';
const { contextBridge } = require('electron');

// Expanded in Task 3. Presence of window.cuelist is how the renderer detects Electron.
contextBridge.exposeInMainWorld('cuelist', {
  isDesktop: true,
});
