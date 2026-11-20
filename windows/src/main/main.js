'use strict';

const electron = require('electron');
const path = require('path');
const { Store } = require('./store');
const { Engine } = require('./engine');
const { UpdateService } = require('./updates');

const {
  app,
  BrowserWindow,
  Tray,
  Menu,
  Notification,
  nativeImage,
  ipcMain,
  shell,
  clipboard,
  dialog,
  session,
} = electron;

const APP_ID = 'com.hunao.autodl';
const LOGIN_PARTITION = 'hunao-login';
const REPO_URL = 'https://github.com/A2ureeE/CrazyAutoDL';
const isDemo = process.argv.includes('--demo');
const isDev = !app.isPackaged;

app.setAppUserModelId(APP_ID);

let mainWindow = null;
let loginWindow = null;
let tray = null;
let store = null;
let engine = null;
let updater = null;
let loginPoller = null;
let lastAttemptedToken = null;
let isQuitting = false;
let trayHintShown = false;
let trayUpdateTimer = null;
let lastTrayMenuSignature = '';
let latestState = null;

function iconPath() {
  return path.join(app.getAppPath(), 'build', 'icon.png');
}

function mainIcon() {
  try {
    return nativeImage.createFromPath(iconPath());
  } catch {
    return nativeImage.createEmpty();
  }
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    showMainWindow();
  });

  app.whenReady().then(initialize).catch((error) => {
    console.error('[main] initialization failed:', error);
    dialog.showErrorBox('胡闹AutoDL 启动失败', error && error.message ? error.message : String(error));
    app.quit();
  });

  app.on('activate', () => {
    if (mainWindow) showMainWindow();
  });

  app.on('window-all-closed', () => {
    // Stay in the tray so GPU watching continues after the window is closed.
  });

  app.on('before-quit', () => {
    isQuitting = true;
    stopLoginPolling();
    if (engine) engine.destroy();
    if (trayUpdateTimer) clearTimeout(trayUpdateTimer);
  });
}

async function initialize() {
  Menu.setApplicationMenu(null);
  store = new Store();
  engine = new Engine({
    store,
    demoMode: isDemo,
    appVersion: app.getVersion(),
    notify: showNotification,
    onSessionCleared: clearLoginSession,
  });
  updater = new UpdateService({ store, demoMode: isDemo });

  createMainWindow();
  registerIpc();
  createTray();

  engine.on('state', () => broadcast());
  engine.on('toast', (toast) => sendToRenderer('toast', toast));
  updater.on('state', () => broadcast());
  updater.on('notice', (notice) => sendToRenderer('toast', { id: `updater-${Date.now()}`, ...notice }));
  updater.on('available', (state) => {
    if (!state.userInitiated && state.release) {
      sendToRenderer('toast', {
        id: `update-${Date.now()}`,
        kind: 'info',
        title: `发现新版本 ${state.release.version}`,
        message: '打开「设置 → 版本更新」即可在应用内完成更新。',
      });
    }
  });
  updater.on('ready', (state) => {
    showNotification({
      title: '更新已下载完成',
      body: `胡闹AutoDL ${state.release ? state.release.version : ''} 已准备就绪，重启应用即可完成安装。`,
      tag: 'update-ready',
    });
  });

  broadcast();
  if (!isDemo) updater.autoCheckIfNeeded();
}

function createMainWindow() {
  mainWindow = new BrowserWindow({
    width: 1360,
    height: 900,
    minWidth: 1080,
    minHeight: 720,
    show: false,
    title: '胡闹AutoDL',
    icon: mainIcon(),
    backgroundColor: '#070d0f',
    titleBarStyle: 'hidden',
    titleBarOverlay: {
      color: '#070d0f',
      symbolColor: '#d6eeeb',
      height: 40,
    },
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: false,
      devTools: isDev,
    },
  });

  mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));
  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
    if (isDev && process.argv.includes('--devtools')) {
      mainWindow.webContents.openDevTools({ mode: 'detach' });
    }
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    openExternalSafe(url);
    return { action: 'deny' };
  });
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (!url.startsWith('file:')) event.preventDefault();
  });
  mainWindow.webContents.on('render-process-gone', (event, details) => {
    console.error('[main] renderer gone:', details);
  });

  mainWindow.on('close', (event) => {
    if (isQuitting) return;
    event.preventDefault();
    mainWindow.hide();
    if (!trayHintShown) {
      trayHintShown = true;
      showNotification({
        title: '胡闹AutoDL 正在后台守护',
        body: '窗口已最小化到系统托盘，双击托盘图标可重新打开。',
        tag: 'tray-hint',
      });
    }
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

function showMainWindow() {
  if (!mainWindow || mainWindow.isDestroyed()) {
    createMainWindow();
    return;
  }
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.show();
  mainWindow.focus();
  broadcast();
}

function sendToRenderer(channel, payload) {
  if (mainWindow && !mainWindow.isDestroyed() && !mainWindow.webContents.isDestroyed()) {
    mainWindow.webContents.send(channel, payload);
  }
}

function currentState() {
  const state = engine ? engine.buildState() : { phase: 'checking' };
  return {
    ...state,
    update: updater ? updater.snapshot() : null,
    loginWindowOpen: Boolean(loginWindow && !loginWindow.isDestroyed()),
    notificationsSupported: Notification.isSupported(),
    platform: process.platform,
  };
}

function broadcast() {
  const state = currentState();
  latestState = state;
  sendToRenderer('state', state);
  scheduleTrayUpdate(state);
}

function scheduleTrayUpdate(state) {
  if (!tray) return;
  if (trayUpdateTimer) return;
  trayUpdateTimer = setTimeout(() => {
    trayUpdateTimer = null;
    updateTray(latestState || state);
  }, 400);
}

function createTray() {
  const image = mainIcon();
  tray = new Tray(image.isEmpty() ? nativeImage.createEmpty() : image.resize({ width: 16, height: 16 }));
  tray.setToolTip('胡闹AutoDL · 正在准备监控');
  tray.on('click', showMainWindow);
  tray.on('double-click', showMainWindow);
  updateTray(currentState());
}

function updateTray(state) {
  if (!tray) return;
  const phase = state.phase;
  const selected = state.selectedInstance;
  let status = '未登录 AutoDL';
  let tooltip = '胡闹AutoDL';
  if (phase === 'checking') {
    status = '正在连接 AutoDL…';
    tooltip = '胡闹AutoDL · 正在连接';
  } else if (phase === 'signedIn') {
    if (selected) {
      const idle = state.stock ? `${state.stock.idleGPUs} 张空闲 ${state.stock.gpuName}` : '显卡状态同步中';
      status = `${selected.name} · ${selected.stateLabel} · ${idle}`;
      tooltip = `胡闹AutoDL · ${selected.name} · ${selected.stateLabel}`;
    } else {
      status = `已登录 · ${state.instances.length} 个实例`;
      tooltip = '胡闹AutoDL · 等待选择监控目标';
    }
    if (state.isDemo) status = `演示模式 · ${status}`;
  }
  tray.setToolTip(tooltip);

  const update = state.update || {};
  let updateItem = { label: '检查更新…', click: () => focusAndNavigate('settings', () => updater.check({ userInitiated: true })) };
  if (update.phase === 'checking') {
    updateItem = { label: '正在检查更新…', enabled: false };
  } else if (update.phase === 'downloading') {
    updateItem = {
      label: `正在下载更新 ${Math.round((update.progress || 0) * 100)}%`,
      click: () => focusAndNavigate('settings'),
    };
  } else if (update.phase === 'available' && update.release) {
    updateItem = {
      label: `发现新版本 v${update.release.version} · 去更新`,
      click: () => focusAndNavigate('settings'),
    };
  } else if (update.phase === 'readyToInstall' && update.release) {
    updateItem = {
      label: `更新 v${update.release.version} 已就绪 · 重启安装`,
      click: () => focusAndNavigate('settings'),
    };
  }

  const template = [
    { label: '胡闹AutoDL', enabled: false },
    { label: status, enabled: false },
    { type: 'separator' },
    { label: '打开监控台', click: showMainWindow },
    {
      label: '立即刷新',
      enabled: phase === 'signedIn',
      click: () => {
        if (engine) engine.refreshNow();
      },
    },
    {
      label: '自动开机',
      type: 'checkbox',
      checked: Boolean(state.autoStartEnabled),
      enabled: phase === 'signedIn',
      click: (item) => {
        if (engine) engine.setAutoStart(item.checked);
      },
    },
    { type: 'separator' },
    updateItem,
    {
      label: '在 GitHub 点个 Star',
      click: () => openExternalSafe(REPO_URL),
    },
    { type: 'separator' },
    {
      label: '退出胡闹AutoDL',
      click: () => {
        isQuitting = true;
        app.quit();
      },
    },
  ];

  const signature = JSON.stringify(template);
  if (signature === lastTrayMenuSignature) return;
  lastTrayMenuSignature = signature;
  tray.setContextMenu(Menu.buildFromTemplate(template));
}

function focusAndNavigate(section, beforeNavigate) {
  showMainWindow();
  sendToRenderer('navigate', section);
  if (beforeNavigate) beforeNavigate();
}

function showNotification({ title, body, tag }) {
  if (!Notification.isSupported()) return false;
  try {
    const notification = new Notification({
      title: String(title || '胡闹AutoDL'),
      body: String(body || ''),
      icon: mainIcon(),
      timeoutType: 'default',
    });
    notification.on('click', showMainWindow);
    notification.show();
    return true;
  } catch (error) {
    console.error('[notify] failed:', error);
    return false;
  }
}

// ------------------------------------------------------------------- login

function clearLoginSession() {
  stopLoginPolling();
  if (loginWindow && !loginWindow.isDestroyed()) {
    loginWindow.close();
  }
  loginWindow = null;
  try {
    session.fromPartition(LOGIN_PARTITION).clearStorageData();
    session.fromPartition(LOGIN_PARTITION).clearCache();
  } catch (error) {
    console.error('[login] failed to clear session:', error);
  }
}

function openLoginWindow() {
  if (engine && engine.phase === 'signedIn') {
    showMainWindow();
    return { ok: true, alreadySignedIn: true };
  }
  if (loginWindow && !loginWindow.isDestroyed()) {
    loginWindow.show();
    loginWindow.focus();
    return { ok: true, alreadyOpen: true };
  }

  const loginSession = session.fromPartition(LOGIN_PARTITION);
  loginSession.clearStorageData();
  lastAttemptedToken = null;

  loginWindow = new BrowserWindow({
    width: 1080,
    height: 800,
    minWidth: 880,
    minHeight: 620,
    show: false,
    title: '登录 AutoDL · 胡闹AutoDL',
    icon: mainIcon(),
    backgroundColor: '#0a1114',
    autoHideMenuBar: true,
    webPreferences: {
      partition: LOGIN_PARTITION,
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      devTools: isDev,
    },
  });
  loginWindow.setMenuBarVisibility(false);
  loginWindow.once('ready-to-show', () => loginWindow.show());

  loginWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (isAutoDLUrl(url)) {
      loginWindow.loadURL(url).catch((error) => console.error('[login] popup failed:', error));
    } else {
      openExternalSafe(url);
    }
    return { action: 'deny' };
  });
  loginWindow.webContents.on('will-navigate', (event, url) => {
    if (!isAutoDLUrl(url)) event.preventDefault();
  });
  loginWindow.on('closed', () => {
    stopLoginPolling();
    loginWindow = null;
    broadcast();
  });

  loginWindow.loadURL('https://www.autodl.com/login').catch((error) => {
    console.error('[login] failed to load:', error);
  });
  startLoginPolling();
  broadcast();
  return { ok: true };
}

function startLoginPolling() {
  stopLoginPolling();
  loginPoller = setInterval(async () => {
    if (!loginWindow || loginWindow.isDestroyed()) {
      stopLoginPolling();
      return;
    }
    let auth = null;
    try {
      auth = await loginWindow.webContents.executeJavaScript(TOKEN_SCAN_SCRIPT, true);
    } catch {
      return;
    }
    if (!auth || !auth.token) return;
    const attemptKey = `${auth.token}|${auth.account && auth.account.subName ? auth.account.subName : ''}`;
    if (attemptKey === lastAttemptedToken) return;
    lastAttemptedToken = attemptKey;
    const result = await engine.signIn(auth);
    if (result && result.ok && loginWindow && !loginWindow.isDestroyed()) {
      const finishedWindow = loginWindow;
      loginWindow = null;
      stopLoginPolling();
      finishedWindow.close();
      clearLoginSessionStorage();
      broadcast();
    }
  }, 1200);
}

function stopLoginPolling() {
  if (loginPoller) {
    clearInterval(loginPoller);
    loginPoller = null;
  }
}

function clearLoginSessionStorage() {
  try {
    session.fromPartition(LOGIN_PARTITION).clearStorageData();
  } catch {
    // Best effort: the partition is in-memory and dies with the app anyway.
  }
}

function isAutoDLUrl(rawUrl) {
  try {
    const url = new URL(rawUrl);
    return url.protocol === 'https:' && (url.hostname === 'autodl.com' || url.hostname.endsWith('.autodl.com'));
  } catch {
    return false;
  }
}

const TOKEN_SCAN_SCRIPT = `(() => {
  try {
    const path = String(window.location.pathname || '');
    if (path.indexOf('/login') === 0 || path.indexOf('/register') === 0 || path.indexOf('/forget') === 0) {
      return null;
    }
    const keys = ['token', 'Token', 'access_token', 'autodl_token', 'Authorization'];
    let token = null;
    for (let i = 0; i < keys.length; i++) {
      const raw = window.localStorage.getItem(keys[i]);
      if (!raw) continue;
      const candidate = String(raw).trim().replace(/^["']|["']$/g, '');
      if (candidate.length >= 12 && candidate.indexOf(' ') < 0 && candidate.charAt(0) !== '{') {
        token = candidate;
        break;
      }
    }
    if (!token) return null;
    let subName = '';
    try {
      const user = JSON.parse(window.localStorage.getItem('user') || '{}');
      if (user && typeof user.sub_name === 'string') subName = user.sub_name.trim();
    } catch (e) {}
    return { token, account: subName ? { subName } : null };
  } catch (e) {}
  return null;
})()`;

// --------------------------------------------------------------------- IPC

function registerIpc() {
  ipcMain.handle('state:get', () => currentState());

  ipcMain.handle('app:open-external', (event, url) => openExternalSafe(url));
  ipcMain.handle('clipboard:write', (event, text) => {
    clipboard.writeText(String(text || ''));
    return true;
  });
  ipcMain.handle('dialog:confirm', async (event, options) => {
    const safe = options && typeof options === 'object' ? options : {};
    const dialogOptions = {
      type: 'warning',
      title: clip(safe.title, 80) || '胡闹AutoDL',
      message: clip(safe.message, 200) || '确认执行此操作？',
      detail: clip(safe.detail, 600) || '',
      buttons: [clip(safe.confirmLabel, 30) || '确认', clip(safe.cancelLabel, 30) || '取消'],
      defaultId: 1,
      cancelId: 1,
      noLink: true,
    };
    const result =
      mainWindow && !mainWindow.isDestroyed()
        ? await dialog.showMessageBox(mainWindow, dialogOptions)
        : await dialog.showMessageBox(dialogOptions);
    return result.response === 0;
  });

  ipcMain.handle('auth:sign-in', async (event, auth) => {
    const result = await engine.signIn(auth);
    if (result.ok) {
      clearLoginSession();
      showMainWindow();
    }
    return result;
  });
  ipcMain.handle('auth:start-browser-login', () => openLoginWindow());
  ipcMain.handle('auth:logout', () => {
    engine.logout();
    return true;
  });

  ipcMain.handle('instance:select', (event, id) => {
    engine.selectInstance(String(id || ''));
    return true;
  });
  ipcMain.handle('instance:power-on', (event, id) => {
    engine.powerOn(String(id || ''));
    return true;
  });
  ipcMain.handle('instance:power-off', (event, id) => {
    engine.powerOff(String(id || ''));
    return true;
  });
  ipcMain.handle('engine:refresh', () => {
    engine.refreshNow();
    return true;
  });
  ipcMain.handle('billing:refresh', (event, force) => {
    engine.refreshBilling(Boolean(force));
    return true;
  });

  ipcMain.handle('settings:auto-start', (event, enabled) => {
    engine.setAutoStart(Boolean(enabled));
    return true;
  });
  ipcMain.handle('settings:poll-interval', (event, seconds) => {
    engine.setPollInterval(seconds);
    return true;
  });
  ipcMain.handle('settings:low-balance', (event, value) => {
    engine.setLowBalanceThreshold(value);
    return true;
  });
  ipcMain.handle('notifications:test', () => engine.sendTestNotification());

  ipcMain.handle('update:get', () => updater.snapshot());
  ipcMain.handle('update:check', () => {
    updater.check({ userInitiated: true });
    return true;
  });
  ipcMain.handle('update:download', () => {
    updater.download();
    return true;
  });
  ipcMain.handle('update:install', () => {
    updater.install();
    return true;
  });
}

function clip(value, max) {
  if (typeof value !== 'string') return '';
  return value.slice(0, max);
}

function openExternalSafe(rawUrl) {
  if (typeof rawUrl !== 'string') return false;
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    return false;
  }
  if (url.protocol !== 'https:') return false;
  const allowed =
    url.hostname === 'github.com' ||
    url.hostname.endsWith('.github.com') ||
    url.hostname === 'autodl.com' ||
    url.hostname.endsWith('.autodl.com');
  if (!allowed) return false;
  shell.openExternal(url.toString()).catch((error) => {
    console.error('[main] failed to open link:', error);
  });
  return true;
}

process.on('uncaughtException', (error) => {
  console.error('[main] uncaught exception:', error);
});
process.on('unhandledRejection', (reason) => {
  console.error('[main] unhandled rejection:', reason);
});
