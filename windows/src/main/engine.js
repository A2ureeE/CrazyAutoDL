'use strict';

const { EventEmitter } = require('events');
const { AutoDLAPI, userMessage, defaultBillingRange, AutoDLError } = require('./api');
const { maskToken } = require('./store');
const {
  instanceState,
  instanceView,
  balanceView,
  stockView,
  billingView,
  BillingSnapshot,
  formatFullDate,
  formatRelative,
  formatTime,
} = require('./models');
const demo = require('./demo');

const MIN_POLL_INTERVAL = 8;
const MAX_POLL_INTERVAL = 120;
const AUTO_START_COOLDOWN_MS = 60 * 1000;

function normalizeAuth(rawAuth, fallbackAccount) {
  if (rawAuth && typeof rawAuth === 'object' && !Array.isArray(rawAuth)) {
    const token = String(rawAuth.token || '').trim();
    const subName = String(
      rawAuth.account && rawAuth.account.subName
        ? rawAuth.account.subName
        : rawAuth.subName || ''
    ).trim();
    return { token, account: subName ? { subName } : null };
  }
  const token = String(rawAuth || '').trim();
  const subName = fallbackAccount && typeof fallbackAccount.subName === 'string'
    ? fallbackAccount.subName.trim()
    : '';
  return { token, account: subName ? { subName } : null };
}

class Engine extends EventEmitter {
  constructor({ store, demoMode, notify, onSessionCleared, appVersion }) {
    super();
    this.store = store;
    this.demoMode = Boolean(demoMode);
    this.notifyHook = notify || (() => false);
    this.onSessionCleared = onSessionCleared || (() => {});
    this.appVersion = appVersion;

    this.phase = 'checking';
    this.instances = [];
    this.selectedInstanceId = store.selectedInstanceId;
    this.stock = null;
    this.balance = null;
    this.balanceError = null;
    this.billing = null;
    this.billingError = null;
    this.isBillingLoading = false;
    this.isRefreshing = false;
    this.lastUpdated = null;
    this.lastError = null;
    this.activity = [];
    this.isLoggingIn = false;
    this.loginError = null;
    this.token = null;
    this.account = null;
    this.subAccount = false;
    this.tokenHint = '';
    this.signedInAt = null;
    this.actionInstanceId = null;
    this.isAutoStarting = false;
    this.autoStartEnabled = store.autoStartEnabled;
    this.pollInterval = store.pollingInterval;
    this.lowBalanceThreshold = store.lowBalanceThreshold;
    this.gpuWasAvailable = false;
    this.didNotifyForAvailability = false;
    this.didNotifyForLowBalance = false;
    this.lastAutoAttemptAt = null;
    this.consecutiveErrors = 0;
    this.activitySequence = 0;
    this.monitorGeneration = 0;
    this.monitorStopped = true;
    this.destroyed = false;

    if (this.demoMode) {
      this.phase = 'loggedOut';
      this.applyDemo();
      return;
    }

    const savedToken = store.getToken();
    if (savedToken) {
      this.token = savedToken;
      this.account = store.getAccount();
      this.subAccount = Boolean(this.account && this.account.subName);
      this.tokenHint = maskToken(savedToken);
      this.phase = 'checking';
      this.connectWithToken(savedToken, { persist: false, bootstrap: true, account: this.account }).catch((error) => {
        console.error('[engine] bootstrap failed:', error);
      });
    } else {
      this.phase = 'loggedOut';
    }
  }

  applyDemo() {
    const seed = demo.seed();
    this.phase = 'signedIn';
    this.signedInAt = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000);
    this.instances = seed.instances;
    this.selectedInstanceId = seed.selectedInstanceId;
    this.stock = seed.stock;
    this.balance = seed.balance;
    this.billing = new BillingSnapshot(seed.billing.records, seed.billing.fetchedAt);
    this.activity = seed.activity;
    this.lastUpdated = new Date();
    this.tokenHint = 'demo••••••••';
    this.autoStartEnabled = true;
    this.pollInterval = 15;
    this.emitState();
  }

  destroy() {
    this.destroyed = true;
    this.stopMonitoring();
    this.removeAllListeners();
  }

  // ---------------------------------------------------------------- session

  async connectWithToken(rawAuth, { persist, bootstrap, account } = {}) {
    const auth = normalizeAuth(rawAuth, account);
    const candidate = auth.token;
    if (!candidate) return { ok: false, error: '请输入 AutoDL Token' };
    if (this.isLoggingIn) return { ok: false, error: '正在连接，请稍候' };

    this.isLoggingIn = true;
    this.loginError = null;
    this.emitState();

    const api = new AutoDLAPI(candidate, { subAccount: Boolean(auth.account && auth.account.subName) });
    try {
      const list = await api.fetchInstances();
      this.token = candidate;
      this.account = auth.account;
      this.subAccount = Boolean(auth.account && auth.account.subName);
      this.tokenHint = maskToken(candidate);
      if (persist) this.store.saveAuth(candidate, auth.account);
      this.phase = 'signedIn';
      this.signedInAt = new Date();
      this.loginError = null;
      this.lastError = null;
      this.applyInstances(list);
      this.addActivity(
        'success',
        bootstrap ? '已自动连接 AutoDL' : '登录成功',
        list.length === 0 ? '账号下暂无实例' : `正在守护 ${list.length} 个实例`
      );
      if (list.length === 0) {
        this.addActivity('info', '账号下暂无实例', '请先在 AutoDL 控制台创建实例');
      }
      this.isLoggingIn = false;
      this.emitState();
      this.startMonitoring(true);
      return { ok: true, count: list.length };
    } catch (error) {
      const message = userMessage(error);
      this.isLoggingIn = false;
      if (error instanceof AutoDLError && error.isAuthFailure) {
        if (bootstrap) {
          this.expireSession(message);
        } else {
          this.loginError = 'Token 无效或已过期，请重新登录 AutoDL';
          this.emitState();
        }
        return { ok: false, error: this.loginError || message };
      }

      if (bootstrap) {
        this.token = candidate;
        this.account = auth.account;
        this.subAccount = Boolean(auth.account && auth.account.subName);
        this.tokenHint = maskToken(candidate);
        this.phase = 'signedIn';
        this.signedInAt = new Date();
        this.lastError = message;
        this.addActivity('error', '首次同步失败', message);
        this.emitState();
        this.startMonitoring(true);
        return { ok: true, offline: true };
      }

      this.loginError = message;
      this.emitState();
      return { ok: false, error: message };
    }
  }

  async signIn(rawToken) {
    return this.connectWithToken(rawToken, { persist: true, bootstrap: false });
  }

  logout() {
    if (this.demoMode) {
      this.emitToast('info', '演示模式', '演示数据不会退出登录。');
      return;
    }
    this.stopMonitoring();
    this.token = null;
    this.account = null;
    this.subAccount = false;
    this.tokenHint = '';
    this.store.deleteToken();
    this.onSessionCleared();
    this.phase = 'loggedOut';
    this.signedInAt = null;
    this.instances = [];
    this.selectedInstanceId = null;
    this.stock = null;
    this.lastUpdated = null;
    this.lastError = null;
    this.loginError = null;
    this.isRefreshing = false;
    this.activity = [];
    this.balance = null;
    this.balanceError = null;
    this.billing = null;
    this.billingError = null;
    this.isBillingLoading = false;
    this.gpuWasAvailable = false;
    this.didNotifyForAvailability = false;
    this.didNotifyForLowBalance = false;
    this.lastAutoAttemptAt = null;
    this.store.setSelectedInstance(null);
    this.emitState();
  }

  expireSession(reason) {
    this.stopMonitoring();
    this.token = null;
    this.account = null;
    this.subAccount = false;
    this.tokenHint = '';
    this.store.deleteToken();
    this.onSessionCleared();
    this.phase = 'loggedOut';
    this.signedInAt = null;
    this.stock = null;
    this.balance = null;
    this.balanceError = null;
    this.billing = null;
    this.billingError = null;
    this.isBillingLoading = false;
    this.didNotifyForLowBalance = false;
    this.lastUpdated = null;
    this.isRefreshing = false;
    this.loginError = reason;
    this.addActivity('error', '登录已失效', reason);
    this.emitToast('error', '登录已失效', '请重新连接 AutoDL');
    this.emitState();
  }

  // -------------------------------------------------------------- monitoring

  startMonitoring(immediately) {
    const generation = ++this.monitorGeneration;
    this.monitorStopped = false;
    const loop = async () => {
      if (immediately) {
        await this.refreshAll(false);
      }
      while (!this.monitorStopped && generation === this.monitorGeneration) {
        await delay(Math.max(this.pollInterval, MIN_POLL_INTERVAL) * 1000);
        if (this.monitorStopped || generation !== this.monitorGeneration) return;
        await this.refreshAll(false);
      }
    };
    loop().catch((error) => console.error('[engine] monitor loop failed:', error));
  }

  stopMonitoring() {
    this.monitorGeneration += 1;
    this.monitorStopped = true;
  }

  refreshNow() {
    if (this.demoMode) {
      if (this.stock) this.stock.checkedAt = new Date();
      this.lastUpdated = new Date();
      if (this.billing) this.billing.fetchedAt = new Date();
      this.emitState();
      this.emitToast('info', '演示数据已刷新', '当前展示的是内置测试账号，不会请求 AutoDL。');
      return;
    }
    this.refreshAll(true);
  }

  async refreshAll(userInitiated = false) {
    if (this.demoMode || this.phase !== 'signedIn' || !this.token) return;
    if (this.isRefreshing) return;

    const token = this.token;
    this.isRefreshing = true;
    this.emitState();

    try {
      const list = await new AutoDLAPI(token, { subAccount: this.subAccount }).fetchInstances();
      if (this.token !== token || this.phase !== 'signedIn') return;

      this.applyInstances(list);
      this.lastError = null;
      this.consecutiveErrors = 0;

      try {
        const latestBalance = await new AutoDLAPI(token, { subAccount: this.subAccount }).fetchBalance();
        if (this.token !== token || this.phase !== 'signedIn') return;
        this.balance = latestBalance;
        this.balanceError = null;
        this.evaluateBalanceAlert();
      } catch (error) {
        if (error instanceof AutoDLError && error.isAuthFailure) {
          this.expireSession(userMessage(error));
          return;
        }
        this.balanceError = userMessage(error);
      }

      const selected = this.selectedInstance;
      if (!selected) {
        this.stock = null;
        this.lastUpdated = new Date();
        return;
      }

      try {
        const latestStock = await new AutoDLAPI(token, { subAccount: this.subAccount }).fetchGPUStock(selected);
        if (this.token !== token || this.phase !== 'signedIn') return;
        this.stock = latestStock;
        this.lastUpdated = new Date();
        this.evaluateStock(latestStock, selected);
      } catch (error) {
        if (error instanceof AutoDLError && error.isAuthFailure) {
          this.expireSession(userMessage(error));
          return;
        }
        this.lastError = `显卡状态同步失败：${userMessage(error)}`;
        this.stock = null;
        this.lastUpdated = new Date();
        this.registerFailure(this.lastError);
      }
    } catch (error) {
      if (error instanceof AutoDLError && error.isAuthFailure) {
        this.expireSession(userMessage(error));
        return;
      }
      this.lastError = userMessage(error);
      this.registerFailure(this.lastError);
      if (userInitiated) {
        this.emitToast('error', '同步失败', this.lastError);
      }
    } finally {
      this.isRefreshing = false;
      this.emitState();
    }
  }

  // ----------------------------------------------------------------- billing

  async refreshBilling(force = false) {
    if (this.phase !== 'signedIn') return;
    if (this.demoMode) {
      if (this.billing) this.billing.fetchedAt = new Date();
      this.emitState();
      this.emitToast('info', '演示账单已是最新', '内置测试账号的近 35 天流水已加载。');
      return;
    }
    if (this.isBillingLoading) return;
    if (!force && this.billing && Date.now() - this.billing.fetchedAt.getTime() < 120 * 1000) {
      return;
    }

    const token = this.token;
    this.isBillingLoading = true;
    this.emitState();

    try {
      const { start, end } = defaultBillingRange();
      const records = await new AutoDLAPI(token, { subAccount: this.subAccount }).fetchBills(start, end);
      if (this.token !== token || this.phase !== 'signedIn') return;
      this.billing = new BillingSnapshot(records, new Date());
      this.billingError = null;
    } catch (error) {
      if (error instanceof AutoDLError && error.isAuthFailure) {
        this.expireSession(userMessage(error));
        return;
      }
      if (this.token !== token || this.phase !== 'signedIn') return;
      this.billingError = userMessage(error);
    } finally {
      this.isBillingLoading = false;
      this.emitState();
    }
  }

  // --------------------------------------------------------------- selection

  applyInstances(list) {
    this.instances = list;
    const previousSelection = this.selectedInstanceId;
    const stored = this.store.selectedInstanceId;

    let next = list.find((instance) => instance.id === stored) || null;
    if (!next && previousSelection) {
      next = list.find((instance) => instance.id === previousSelection) || null;
    }
    if (!next) next = list[0] || null;

    this.selectedInstanceId = next ? next.id : null;
    if (next && next.id !== stored) this.store.setSelectedInstance(next.id);

    if ((next ? next.id : null) !== previousSelection) {
      this.stock = null;
      this.lastUpdated = null;
      this.gpuWasAvailable = false;
      this.didNotifyForAvailability = false;
      this.lastAutoAttemptAt = null;
    }
  }

  selectInstance(id) {
    if (id === this.selectedInstanceId) return;
    const instance = this.instances.find((item) => item.id === id);
    if (!instance) return;
    this.selectedInstanceId = id;
    this.store.setSelectedInstance(id);
    this.stock = null;
    this.lastUpdated = null;
    this.lastError = null;
    this.gpuWasAvailable = false;
    this.didNotifyForAvailability = false;
    this.lastAutoAttemptAt = null;
    this.addActivity('info', '已切换监控目标', `${instance.name} · ${instance.gpuName}`);
    this.emitState();
    if (!this.demoMode) this.refreshAll(true);
  }

  get selectedInstance() {
    if (!this.selectedInstanceId) return null;
    return this.instances.find((instance) => instance.id === this.selectedInstanceId) || null;
  }

  // -------------------------------------------------------------- automation

  evaluateStock(stock, instance) {
    const available =
      stock.machineFound && stock.idleGPUs > 0 && stock.idleGPUs >= Math.max(stock.requiredGPUs, 1);
    const isPoweredOff = instanceState(instance.rawStatus) === 'stopped';

    if (available && !this.gpuWasAvailable) {
      this.addActivity(
        'warning',
        '发现空闲显卡',
        `${instance.machineID} · ${stock.idleGPUs} 张 ${instance.gpuName} 空闲`
      );
      if (this.autoStartEnabled) {
        this.addActivity('info', '自动开机已触发', '正在尝试抢占空闲 GPU');
      }
    }

    this.gpuWasAvailable = available;
    if (!available) {
      this.didNotifyForAvailability = false;
      return;
    }
    if (!isPoweredOff) return;

    if (this.autoStartEnabled) {
      this.attemptAutoPowerOn(instance, stock);
    } else if (!this.didNotifyForAvailability) {
      this.didNotifyForAvailability = true;
      this.notifyGPUAvailable(instance, stock);
    }
  }

  notifyGPUAvailable(instance, stock) {
    const title = '发现空闲 GPU';
    const body = `${instance.name} 所在主机有 ${stock.idleGPUs} 张 ${instance.gpuName} 空闲，自动开机已关闭。`;
    this.addActivity('warning', '已发送空闲提醒', body);
    this.emitToast('warning', title, body);
    this.notifyHook({ title, body, tag: `gpu-available-${instance.id}` });
  }

  setAutoStart(enabled) {
    const next = Boolean(enabled);
    if (this.autoStartEnabled === next) return;
    this.autoStartEnabled = next;
    if (!this.demoMode) this.store.setAutoStart(next);

    if (next) {
      this.addActivity('info', '自动开机已开启', '检测到空闲显卡后自动抢占');
      const instance = this.selectedInstance;
      if (instance && instanceState(instance.rawStatus) === 'stopped' && this.stock) {
        const available =
          this.stock.machineFound &&
          this.stock.idleGPUs > 0 &&
          this.stock.idleGPUs >= Math.max(this.stock.requiredGPUs, 1);
        if (available) this.attemptAutoPowerOn(instance, this.stock);
      }
    } else {
      this.addActivity('info', '自动开机已关闭', '之后仅在有卡空闲时提醒');
      const instance = this.selectedInstance;
      const stock = this.stock ? stockView(this.stock) : null;
      if (
        instance &&
        instanceState(instance.rawStatus) === 'stopped' &&
        stock &&
        stock.isAvailable &&
        !this.didNotifyForAvailability
      ) {
        this.didNotifyForAvailability = true;
        this.notifyGPUAvailable(instance, this.stock);
      }
    }
    this.emitState();
  }

  setPollInterval(seconds) {
    const normalized = Math.min(Math.max(Math.round(Number(seconds) || 0), MIN_POLL_INTERVAL), MAX_POLL_INTERVAL);
    if (normalized === this.pollInterval) return;
    this.pollInterval = normalized;
    if (!this.demoMode) this.store.setPollInterval(normalized);
    this.addActivity('info', '刷新间隔已调整', `每 ${normalized} 秒检查一次`);
    this.emitState();
    if (!this.demoMode && this.phase === 'signedIn') this.startMonitoring(false);
  }

  setLowBalanceThreshold(value) {
    const normalized = Math.min(Math.max(Math.round((Number(value) || 0) * 100) / 100, 1), 10000);
    if (Math.abs(normalized - this.lowBalanceThreshold) < 0.001) return;
    this.lowBalanceThreshold = normalized;
    if (!this.demoMode) this.store.setLowBalanceThreshold(normalized);
    this.addActivity('info', '余额提醒阈值已更新', `可用余额低于 ¥${normalized.toFixed(2)} 时提醒`);
    this.emitState();
    if (!this.balance) return;
    const available = Math.max(0, this.balance.cash) + Math.max(0, this.balance.voucher);
    if (available >= normalized) {
      this.didNotifyForLowBalance = false;
    } else {
      this.evaluateBalanceAlert();
    }
  }

  evaluateBalanceAlert() {
    if (!this.balance) return;
    const available = Math.max(0, this.balance.cash) + Math.max(0, this.balance.voucher);
    if (available >= this.lowBalanceThreshold) {
      this.didNotifyForLowBalance = false;
      return;
    }
    if (this.didNotifyForLowBalance) return;
    this.didNotifyForLowBalance = true;

    const title = '余额不足提醒';
    const voucherNote =
      this.balance.voucher > 0
        ? `（含代金券 ¥${this.balance.voucher.toFixed(2)}）`
        : '';
    const body = `AutoDL 可用余额 ¥${available.toFixed(2)}${voucherNote}，已低于 ¥${this.lowBalanceThreshold.toFixed(2)}，请及时充值以免影响自动开机。`;
    this.addActivity('warning', title, body);
    this.emitToast('warning', title, body);
    this.notifyHook({ title, body, tag: 'balance-low' });
  }

  async attemptAutoPowerOn(instance, stock) {
    if (this.demoMode) return;
    if (!this.autoStartEnabled || this.phase !== 'signedIn' || this.isAutoStarting) return;
    if (instance.id !== this.selectedInstanceId) return;
    if (instanceState(instance.rawStatus) !== 'stopped') return;
    const available =
      stock.machineFound && stock.idleGPUs > 0 && stock.idleGPUs >= Math.max(stock.requiredGPUs, 1);
    if (!available) return;
    if (this.lastAutoAttemptAt && Date.now() - this.lastAutoAttemptAt.getTime() < AUTO_START_COOLDOWN_MS) {
      return;
    }

    const token = this.token;
    if (!token) return;
    this.isAutoStarting = true;
    this.lastAutoAttemptAt = new Date();
    this.emitState();

    try {
      await new AutoDLAPI(token, { subAccount: this.subAccount }).powerOn(instance.id);
      const title = '自动开机成功';
      const detail = `${instance.name} 正在启动，已抢占 ${stock.idleGPUs} 张空闲 ${instance.gpuName}`;
      this.addActivity('success', title, detail);
      this.emitToast('success', title, detail);
      this.notifyHook({ title, body: detail, tag: `autostart-${instance.id}` });
      setTimeout(() => this.refreshAll(false), 2500);
    } catch (error) {
      if (error instanceof AutoDLError && error.isAuthFailure) {
        this.expireSession(userMessage(error));
        return;
      }
      const detail = userMessage(error);
      this.addActivity('error', '自动开机失败', detail);
      this.emitToast('error', '自动开机失败', detail);
    } finally {
      this.isAutoStarting = false;
      this.emitState();
    }
  }

  async performPowerAction(instance, turnOn) {
    if (!instance) return;
    if (this.demoMode) {
      this.applyDemoPowerAction(instance, turnOn);
      return;
    }
    if (this.phase !== 'signedIn' || this.actionInstanceId || !this.token) return;

    const token = this.token;
    this.actionInstanceId = instance.id;
    this.emitState();

    try {
      const api = new AutoDLAPI(token, { subAccount: this.subAccount });
      if (turnOn) await api.powerOn(instance.id);
      else await api.powerOff(instance.id);
      const title = turnOn ? '开机指令已发送' : '关机指令已发送';
      this.addActivity('success', title, instance.name);
      this.emitToast('success', title, `${instance.name} 状态将在几秒后同步。`);
      setTimeout(() => this.refreshAll(false), 2000);
    } catch (error) {
      if (error instanceof AutoDLError && error.isAuthFailure) {
        this.expireSession(userMessage(error));
        return;
      }
      const title = turnOn ? '开机失败' : '关机失败';
      const message = userMessage(error);
      this.addActivity('error', title, message);
      this.emitToast('error', title, message);
    } finally {
      this.actionInstanceId = null;
      this.emitState();
    }
  }

  applyDemoPowerAction(instance, turnOn) {
    const title = turnOn ? '开机指令已发送' : '关机指令已发送';
    instance.rawStatus = turnOn ? 'starting' : 'stopping';
    instance.statusAt = new Date();
    this.actionInstanceId = instance.id;
    this.addActivity('success', title, instance.name);
    this.emitToast('success', title, `${instance.name} 状态将在几秒后同步。`);
    this.emitState();

    setTimeout(() => {
      instance.rawStatus = turnOn ? 'running' : 'shutdown';
      instance.statusAt = new Date();
      if (turnOn) instance.startedAt = new Date();
      this.actionInstanceId = null;
      if (turnOn) {
        this.stock = null;
      } else if (this.stock) {
        this.stock.checkedAt = new Date();
      }
      this.lastUpdated = new Date();
      this.addActivity(turnOn ? 'success' : 'info', turnOn ? '实例已启动' : '实例已关机', instance.name);
      this.emitState();
    }, 2200);
  }

  powerOn(id) {
    const instance = this.instances.find((item) => item.id === id);
    if (!instance) return;
    this.performPowerAction(instance, true);
  }

  powerOff(id) {
    const instance = this.instances.find((item) => item.id === id);
    if (!instance) return;
    this.performPowerAction(instance, false);
  }

  sendTestNotification() {
    const delivered = this.notifyHook({
      title: '胡闹AutoDL 测试通知',
      body: '通知通道正常。发现空闲 GPU 或余额不足时，会在这里提醒你。',
      tag: 'test-notification',
    });
    if (delivered) {
      this.emitToast('info', '测试通知已发送', '如果桌面没有出现横幅，请检查 Windows 通知设置。');
    } else {
      this.emitToast('warning', '通知发送失败', '当前系统不支持通知，或通知已被关闭。');
    }
    return delivered;
  }

  // --------------------------------------------------------------- utilities

  addActivity(kind, title, detail = '') {
    this.activitySequence += 1;
    this.activity.unshift({
      id: `activity-${Date.now()}-${this.activitySequence}`,
      date: new Date(),
      kind,
      title,
      detail,
    });
    if (this.activity.length > 40) this.activity = this.activity.slice(0, 40);
  }

  emitToast(kind, title, message) {
    this.emit('toast', {
      id: `toast-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
      kind,
      title,
      message,
    });
  }

  registerFailure(message) {
    this.consecutiveErrors += 1;
    if (this.consecutiveErrors === 1 || this.consecutiveErrors % 10 === 0) {
      this.addActivity('error', '监控同步异常', message);
    }
  }

  emitState() {
    if (this.destroyed) return;
    this.emit('state', this.buildState());
  }

  buildState() {
    const selectedRaw = this.selectedInstance;
    const selected = instanceView(selectedRaw);
    const stock = stockView(this.stock);
    const balance = balanceView(this.balance);
    const billing = billingView(this.billing, balance ? balance.available : null);
    const isLowBalance = balance ? balance.available < this.lowBalanceThreshold : false;
    const state = selected ? selected.state : null;

    let headline = '等待选择实例';
    let caption = '先在 AutoDL 创建一个实例';
    if (selected) {
      if (!stock) {
        headline = this.lastError ? '显卡状态暂不可用' : '正在读取显卡状态';
        caption = `刷新间隔 ${this.pollInterval} 秒`;
      } else if (state === 'running') {
        headline = '实例正在使用 GPU';
      } else if (state === 'starting') {
        headline = '实例正在启动';
      } else if (state === 'stopping') {
        headline = '实例正在关机';
      } else if (stock.isAvailable) {
        headline = '发现空闲显卡';
      } else if (!stock.machineFound) {
        headline = '目标主机暂未放出空卡';
      } else {
        headline = '正在等待空闲显卡';
      }

      if (stock) {
        if (stock.isAvailable) {
          caption = this.autoStartEnabled ? '自动开机已就绪' : '自动开机已关闭，仅发送提醒';
        } else if (!stock.machineFound) {
          caption = `目标主机 ${selectedRaw.machineID || 'ID 缺失'} 暂无空闲卡`;
        } else {
          caption = `已监测目标主机 · ${this.pollInterval} 秒刷新`;
        }
      }
    }

    let autoStartSubtitle = '只提醒，不自动开机';
    if (this.autoStartEnabled) {
      autoStartSubtitle = state === 'stopped' ? '守候空闲卡，出现即开机' : '等待实例关机后接管';
    }

    return {
      phase: this.phase,
      isDemo: this.demoMode,
      version: this.appVersion,
      todayLabel: formatFullDate(new Date()),
      isLoggingIn: this.isLoggingIn,
      loginError: this.loginError,
      tokenHint: this.tokenHint,
      signedInAt: this.signedInAt ? this.signedInAt.toISOString() : null,
      instances: this.instances.map(instanceView),
      selectedInstanceId: this.selectedInstanceId,
      selectedInstance: selected,
      stock,
      balance,
      balanceError: this.balanceError,
      billing,
      billingError: this.billingError,
      isBillingLoading: this.isBillingLoading,
      isRefreshing: this.isRefreshing,
      isAutoStarting: this.isAutoStarting,
      actionInstanceId: this.actionInstanceId,
      autoStartEnabled: this.autoStartEnabled,
      autoStartSubtitle,
      pollInterval: this.pollInterval,
      lowBalanceThreshold: this.lowBalanceThreshold,
      isLowBalance,
      lastUpdated: this.lastUpdated ? this.lastUpdated.toISOString() : null,
      lastUpdatedLabel: formatRelative(this.lastUpdated),
      lastError: this.lastError,
      availabilityHeadline: headline,
      availabilityCaption: caption,
      runningCount: this.instances.filter((instance) => instanceState(instance.rawStatus) === 'running').length,
      activity: this.activity.slice(0, 12).map((event) => ({
        id: event.id,
        kind: event.kind,
        title: event.title,
        detail: event.detail,
        time: formatTime(event.date),
        date: event.date.toISOString(),
      })),
      activityCount: this.activity.length,
    };
  }
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

module.exports = { Engine };
