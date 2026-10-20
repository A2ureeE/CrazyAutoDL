'use strict';

const { app } = require('electron');
const { EventEmitter } = require('events');
const { autoUpdater } = require('electron-updater');
const { formatRelative } = require('./models');

const AUTO_CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000;
const REPO_URL = 'https://github.com/A2ureeE/CrazyAutoDL';

class UpdateService extends EventEmitter {
  constructor({ store, demoMode }) {
    super();
    this.store = store;
    this.demoMode = Boolean(demoMode);
    this.lastCheckedAt = store.lastUpdateCheckAt;

    this.state = {
      phase: 'idle',
      currentVersion: app.getVersion(),
      release: null,
      progress: 0,
      transferred: 0,
      total: 0,
      bytesPerSecond: 0,
      error: null,
      supported: app.isPackaged,
      isDemo: this.demoMode,
      userInitiated: false,
    };

    autoUpdater.autoDownload = false;
    autoUpdater.autoInstallOnAppQuit = false;
    autoUpdater.allowPrerelease = false;

    autoUpdater.on('update-available', (info) => this.handleAvailable(info));
    autoUpdater.on('update-not-available', () => this.handleNotAvailable());
    autoUpdater.on('download-progress', (progress) => this.handleProgress(progress));
    autoUpdater.on('update-downloaded', (info) => this.handleDownloaded(info));
    autoUpdater.on('error', (error) => this.handleError(error));
  }

  snapshot() {
    return {
      ...this.state,
      lastCheckedAt: this.lastCheckedAt ? this.lastCheckedAt.toISOString() : null,
      lastCheckedLabel: this.lastCheckedAt ? formatRelative(this.lastCheckedAt) : null,
      isBusy: ['checking', 'downloading', 'preparing', 'installing'].includes(this.state.phase),
      isUpdateAvailable: this.state.phase === 'available',
      isReady: this.state.phase === 'readyToInstall',
      repositoryURL: REPO_URL,
    };
  }

  emitState() {
    this.emit('state', this.snapshot());
  }

  async autoCheckIfNeeded() {
    if (this.demoMode || !app.isPackaged) return;
    if (this.lastCheckedAt && Date.now() - this.lastCheckedAt.getTime() < AUTO_CHECK_INTERVAL_MS) {
      return;
    }
    await delay(1800);
    await this.check({ userInitiated: false });
  }

  async check({ userInitiated = true } = {}) {
    if (this.demoMode) {
      if (userInitiated) {
        this.emit('notice', { kind: 'info', title: '演示模式', message: '演示模式不会请求 GitHub 检查更新。' });
      }
      return;
    }
    if (!app.isPackaged) {
      this.state.phase = 'idle';
      this.state.error = null;
      this.emitState();
      if (userInitiated) {
        this.emit('notice', {
          kind: 'info',
          title: '开发模式',
          message: '应用内更新仅在打包后的安装版中可用。',
        });
      }
      return;
    }
    if (['checking', 'downloading', 'preparing', 'installing'].includes(this.state.phase)) return;

    this.state.phase = 'checking';
    this.state.error = null;
    this.state.userInitiated = userInitiated;
    this.emitState();

    try {
      await autoUpdater.checkForUpdates();
    } catch (error) {
      this.handleError(error);
    }
  }

  async download() {
    if (!this.state.release) return;
    if (!['available', 'failed'].includes(this.state.phase)) return;
    this.state.phase = 'downloading';
    this.state.progress = 0;
    this.state.transferred = 0;
    this.state.total = this.state.release ? this.state.release.size : 0;
    this.state.bytesPerSecond = 0;
    this.state.error = null;
    this.emitState();

    try {
      await autoUpdater.downloadUpdate();
    } catch (error) {
      this.handleError(error);
    }
  }

  install() {
    if (this.state.phase !== 'readyToInstall') return;
    this.state.phase = 'installing';
    this.emitState();
    setTimeout(() => {
      try {
        autoUpdater.quitAndInstall(false, true);
      } catch (error) {
        this.handleError(error);
      }
    }, 500);
  }

  handleAvailable(info) {
    this.finishCheck();
    const notes = normalizeNotes(info.releaseNotes);
    this.state.phase = 'available';
    this.state.error = null;
    this.state.release = {
      version: info.version,
      tag: info.tag || `v${info.version}`,
      title: info.releaseName || `胡闹AutoDL v${info.version}`,
      notes,
      pageURL: `${REPO_URL}/releases/tag/v${info.version}`,
      assetName: info.files && info.files[0] ? info.files[0].url : null,
      size: info.files && info.files[0] ? info.files[0].size : 0,
      sizeLabel:
        info.files && info.files[0] && info.files[0].size
          ? formatBytes(info.files[0].size)
          : null,
      releaseDate: info.releaseDate || null,
    };
    this.emitState();
    this.emit('available', this.snapshot());
  }

  handleNotAvailable() {
    this.finishCheck();
    this.state.phase = 'upToDate';
    this.state.release = null;
    this.state.error = null;
    this.emitState();
  }

  handleProgress(progress) {
    if (this.state.phase !== 'downloading') return;
    this.state.phase = 'downloading';
    this.state.progress = Math.min(Math.max((progress.percent || 0) / 100, 0), 1);
    this.state.transferred = progress.transferred || 0;
    this.state.total = progress.total || this.state.total;
    this.state.bytesPerSecond = progress.bytesPerSecond || 0;
    this.state.error = null;
    this.emitState();
  }

  handleDownloaded(info) {
    this.finishCheck();
    this.state.phase = 'readyToInstall';
    this.state.progress = 1;
    this.state.transferred = this.state.total;
    this.state.error = null;
    if (info && info.version && this.state.release) {
      this.state.release.version = info.version;
    }
    this.emitState();
    this.emit('ready', this.snapshot());
  }

  handleError(error) {
    this.finishCheck();
    this.state.phase = 'failed';
    this.state.error = friendlyError(error);
    this.emitState();
  }

  finishCheck() {
    this.lastCheckedAt = new Date();
    try {
      this.store.setLastUpdateCheckAt(this.lastCheckedAt);
    } catch (error) {
      console.error('[updater] failed to persist check time:', error);
    }
  }
}

function normalizeNotes(notes) {
  if (!notes) return '';
  if (typeof notes === 'string') return stripHtml(notes).trim();
  if (Array.isArray(notes)) {
    return notes
      .map((entry) => {
        if (!entry) return '';
        if (typeof entry === 'string') return stripHtml(entry);
        const header = entry.version ? `v${entry.version}\n` : '';
        return `${header}${stripHtml(entry.note || '')}`;
      })
      .join('\n\n')
      .trim();
  }
  return '';
}

function stripHtml(html) {
  return String(html)
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/li>/gi, '\n')
    .replace(/<li>/gi, '· ')
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\n{3,}/g, '\n\n');
}

function friendlyError(error) {
  const message = error && error.message ? String(error.message) : '更新请求失败';
  if (/net::|ENOTFOUND|ECONNREFUSED|ETIMEDOUT|network/i.test(message)) {
    return `无法连接更新服务器：${message}`;
  }
  return message;
}

function formatBytes(bytes) {
  if (!bytes || bytes <= 0) return '—';
  const mb = bytes / (1024 * 1024);
  return mb >= 1 ? `${mb.toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

module.exports = { UpdateService };
