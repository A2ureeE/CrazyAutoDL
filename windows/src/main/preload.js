'use strict';

const { contextBridge, ipcRenderer } = require('electron');

function subscribe(channel, callback) {
  const handler = (event, payload) => callback(payload);
  ipcRenderer.on(channel, handler);
  return () => ipcRenderer.removeListener(channel, handler);
}

contextBridge.exposeInMainWorld('hunao', {
  getState: () => ipcRenderer.invoke('state:get'),
  onState: (callback) => subscribe('state', callback),
  onToast: (callback) => subscribe('toast', callback),
  onNavigate: (callback) => subscribe('navigate', callback),

  refresh: () => ipcRenderer.invoke('engine:refresh'),
  refreshBilling: (force = false) => ipcRenderer.invoke('billing:refresh', force),

  signIn: (token) => ipcRenderer.invoke('auth:sign-in', token),
  startBrowserLogin: () => ipcRenderer.invoke('auth:start-browser-login'),
  logout: () => ipcRenderer.invoke('auth:logout'),

  selectInstance: (id) => ipcRenderer.invoke('instance:select', id),
  powerOn: (id) => ipcRenderer.invoke('instance:power-on', id),
  powerOff: (id) => ipcRenderer.invoke('instance:power-off', id),

  setAutoStart: (enabled) => ipcRenderer.invoke('settings:auto-start', enabled),
  setPollInterval: (seconds) => ipcRenderer.invoke('settings:poll-interval', seconds),
  setLowBalanceThreshold: (value) => ipcRenderer.invoke('settings:low-balance', value),
  testNotification: () => ipcRenderer.invoke('notifications:test'),

  updateCheck: () => ipcRenderer.invoke('update:check'),
  updateDownload: () => ipcRenderer.invoke('update:download'),
  updateInstall: () => ipcRenderer.invoke('update:install'),

  copyText: (text) => ipcRenderer.invoke('clipboard:write', text),
  openExternal: (url) => ipcRenderer.invoke('app:open-external', url),
  confirm: (options) => ipcRenderer.invoke('dialog:confirm', options),
});
