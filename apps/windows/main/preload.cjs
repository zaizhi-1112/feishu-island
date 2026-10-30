'use strict';
// The only bridge between renderer pages and the main process. Whitelisted calls only.
const { contextBridge, ipcRenderer } = require('electron');

const listeners = new Map();
function on(channel, fn) {
  const wrapped = (_event, payload) => fn(payload);
  ipcRenderer.on(channel, wrapped);
  return () => ipcRenderer.removeListener(channel, wrapped);
}

contextBridge.exposeInMainWorld('island', {
  invoke: (method, ...args) => ipcRenderer.invoke('island:invoke', method, args),
  onState: fn => on('island:state', fn),
  onEvent: fn => on('island:event', fn),
  onCompany: fn => on('island:company', fn),
  setIgnoreMouse: ignore => ipcRenderer.send('island:ignore-mouse', !!ignore),
  platform: process.platform
});
