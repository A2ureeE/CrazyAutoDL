'use strict';

const REPO_URL = 'https://github.com/A2ureeE/CrazyAutoDL';
const AUTHOR_URL = 'https://github.com/A2ureeE';
const INSTANCE_CONSOLE_URL = 'https://www.autodl.com/console/instance/list';
const BILLING_CONSOLE_URL = 'https://www.autodl.com/console/bill';

const PALETTE = ['#61fac2', '#54cfff', '#9b85ff', '#ffc257', '#ff7588'];
const ACTIVITY_ICONS = { success: 'check', warning: 'alert', error: 'error', info: 'info' };
const TOAST_ICONS = { success: 'check', warning: 'alert', error: 'error', info: 'info' };
const SECTIONS = ['dashboard', 'instances', 'billing', 'settings'];

const currencyFormatter = new Intl.NumberFormat('zh-CN', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

const dateTimeFormatter = new Intl.DateTimeFormat('zh-CN', {
  timeZone: 'Asia/Shanghai',
  month: 'numeric',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

const els = {
  viewRoot: document.getElementById('view-root'),
  mainScroll: document.getElementById('main-scroll'),
  nav: document.getElementById('nav'),
  navCount: document.getElementById('nav-instance-count'),
  updateBadge: document.getElementById('settings-update-badge'),
  toastRoot: document.getElementById('toast-root'),
  titlebarStatus: document.getElementById('titlebar-status'),
  titlebarDemo: document.getElementById('titlebar-demo'),
  sidebarVersion: document.getElementById('sidebar-version'),
};

let state = null;
let section = 'dashboard';
let billingRange = 14;
let lastEngineSignature = '';
let lastUpdateSignature = '';
let pendingRender = false;
let hasRendered = false;

init();

function init() {
  bindEvents();
  window.hunao.onState(handleIncomingState);
  window.hunao.onToast(showToast);
  window.hunao.onNavigate(navigate);
  window.hunao
    .getState()
    .then(handleIncomingState)
    .catch((error) => {
      console.error('[ui] failed to load state:', error);
      els.viewRoot.innerHTML = `<div class="card billing-error"><h3>界面初始化失败</h3><p>${esc(
        error && error.message ? error.message : '无法连接主进程'
      )}</p></div>`;
    });
}

// ------------------------------------------------------------------ events

function bindEvents() {
  document.addEventListener('click', handleClick);
  document.addEventListener('change', handleChange);
  document.addEventListener('input', handleInput);
  document.addEventListener('keydown', handleKeydown);

  els.viewRoot.addEventListener('focusout', () => {
    window.setTimeout(() => {
      if (pendingRender && !shouldDeferRender()) {
        pendingRender = false;
        renderView();
      }
    }, 160);
  });
}

function handleClick(event) {
  const trigger = event.target.closest('[data-action]');
  if (!trigger) return;
  const action = trigger.dataset.action;

  switch (action) {
    case 'nav':
      navigate(trigger.dataset.section);
      break;
    case 'refresh':
      window.hunao.refresh();
      break;
    case 'billing-refresh':
      window.hunao.refreshBilling(true);
      break;
    case 'browser-login':
      window.hunao.startBrowserLogin();
      break;
    case 'manual-login':
      submitManualToken();
      break;
    case 'logout':
      confirmLogout();
      break;
    case 'select-target':
      if (trigger.tagName === 'BUTTON') window.hunao.selectInstance(trigger.dataset.id || '');
      break;
    case 'power-on':
      window.hunao.powerOn(trigger.dataset.id || '');
      break;
    case 'power-off':
      confirmPowerOff(trigger.dataset.id || '');
      break;
    case 'toggle-auto-start':
      window.hunao.setAutoStart(!(state && state.autoStartEnabled));
      break;
    case 'save-low-balance':
      saveLowBalance();
      break;
    case 'test-notification':
      window.hunao.testNotification();
      break;
    case 'set-range':
      setBillingRange(Number(trigger.dataset.range));
      break;
    case 'update-check':
      window.hunao.updateCheck();
      break;
    case 'update-download':
      window.hunao.updateDownload();
      break;
    case 'update-install':
      window.hunao.updateInstall();
      break;
    case 'open-repo':
      window.hunao.openExternal(REPO_URL);
      break;
    case 'open-releases':
      window.hunao.openExternal(`${REPO_URL}/releases`);
      break;
    case 'open-author':
      window.hunao.openExternal(AUTHOR_URL);
      break;
    case 'open-console':
    case 'open-instance-console':
      window.hunao.openExternal(INSTANCE_CONSOLE_URL);
      break;
    case 'open-billing-console':
      window.hunao.openExternal(BILLING_CONSOLE_URL);
      break;
    case 'release-page':
      openReleasePage();
      break;
    case 'copy-ssh':
    case 'copy-jupyter':
      copyValue(trigger.dataset.value, action === 'copy-ssh' ? 'SSH 命令已复制' : '访问地址已复制');
      break;
    case 'open-jupyter':
      openJupyter(trigger.dataset.url);
      break;
    case 'dismiss-toast': {
      const toast = trigger.closest('.toast');
      if (toast) dismissToast(toast);
      break;
    }
    default:
      break;
  }
}

function handleChange(event) {
  const target = event.target;
  if (target.id === 'poll-range') {
    window.hunao.setPollInterval(Number(target.value));
    return;
  }
  if (target.matches('[data-action="select-target"]')) {
    window.hunao.selectInstance(target.value);
  }
}

function handleInput(event) {
  const target = event.target;
  if (target.id === 'poll-range') {
    const value = Number(target.value) || 8;
    target.style.setProperty('--fill', `${((value - 8) / 112) * 100}%`);
    const label = document.getElementById('poll-value');
    if (label) label.textContent = `${value} 秒`;
  }
}

function handleKeydown(event) {
  const target = event.target;
  if (target.id === 'token-input' && event.key === 'Enter') {
    event.preventDefault();
    submitManualToken();
    return;
  }
  if (target.id === 'low-balance-input' && event.key === 'Enter') {
    event.preventDefault();
    saveLowBalance();
  }
}

// ------------------------------------------------------------------- state

function engineSignature(value) {
  const clone = { ...value };
  delete clone.createdAt;
  delete clone.update;
  delete clone.platform;
  return JSON.stringify(clone);
}

function handleIncomingState(next) {
  if (!next) return;
  const previous = state;
  state = next;

  const nextEngineSignature = engineSignature(next);
  const nextUpdateSignature = JSON.stringify(next.update || null);
  const engineChanged = !previous || nextEngineSignature !== lastEngineSignature;
  const updateChanged = nextUpdateSignature !== lastUpdateSignature;
  lastEngineSignature = nextEngineSignature;
  lastUpdateSignature = nextUpdateSignature;

  document.body.classList.toggle('auth-mode', next.phase !== 'signedIn');
  updateChrome();

  if (engineChanged) {
    if (previous && previous.phase !== next.phase) hasRendered = false;
    if (previous && shouldDeferRender()) {
      pendingRender = true;
    } else {
      pendingRender = false;
      renderView();
    }
    if (previous && previous.phase !== 'signedIn' && next.phase === 'signedIn' && section === 'billing') {
      window.hunao.refreshBilling(false);
    }
  } else if (updateChanged) {
    updateUpdateCard();
  }
}

function shouldDeferRender() {
  const active = document.activeElement;
  if (!active || !els.viewRoot.contains(active)) return false;
  return active.matches('input, select, textarea');
}

function updateChrome() {
  if (!state) return;

  document.querySelectorAll('.nav-item').forEach((item) => {
    item.classList.toggle('active', item.dataset.section === section);
  });

  const instanceCount = Array.isArray(state.instances) ? state.instances.length : 0;
  if (els.navCount) els.navCount.textContent = String(instanceCount);
  if (els.sidebarVersion) els.sidebarVersion.textContent = `v${state.version || '1.2.0'}`;
  if (els.titlebarDemo) els.titlebarDemo.hidden = !state.isDemo;

  const update = state.update;
  if (els.updateBadge) {
    const phase = update && update.phase;
    const visible = phase === 'available' || phase === 'readyToInstall';
    els.updateBadge.hidden = !visible;
    els.updateBadge.textContent = phase === 'readyToInstall' ? 'READY' : 'NEW';
  }

  const status = els.titlebarStatus;
  if (!status) return;
  status.classList.remove('is-busy', 'is-offline');
  let text = '未连接 AutoDL';
  if (state.phase === 'checking') {
    text = '正在连接 AutoDL…';
    status.classList.add('is-busy');
  } else if (state.phase === 'signedIn') {
    if (state.isDemo) {
      text = '演示模式 · 本地数据';
    } else if (state.isRefreshing) {
      text = '正在同步…';
      status.classList.add('is-busy');
    } else if (state.selectedInstance) {
      text = `${state.selectedInstance.name} · ${state.pollInterval}s 刷新`;
    } else {
      text = `实时监控 · ${state.pollInterval}s`;
    }
  } else {
    status.classList.add('is-offline');
  }
  status.innerHTML = `<i class="status-dot"></i><span>${esc(text)}</span>`;
}

function navigate(target) {
  if (!SECTIONS.includes(target)) return;
  const changed = target !== section;
  section = target;
  if (changed) {
    hasRendered = false;
    els.mainScroll.scrollTop = 0;
  }
  if (state) {
    updateChrome();
    if (state.phase === 'signedIn') {
      renderView();
      if (target === 'billing') window.hunao.refreshBilling(false);
    }
  }
}

function renderView() {
  if (!state) return;
  const animate = !hasRendered;
  hasRendered = true;
  els.viewRoot.classList.toggle('no-enter', !animate);

  if (state.phase !== 'signedIn') {
    els.viewRoot.innerHTML = authView();
    return;
  }

  let html = '';
  switch (section) {
    case 'instances':
      html = instancesView();
      break;
    case 'billing':
      html = billingView();
      break;
    case 'settings':
      html = settingsView();
      break;
    default:
      html = dashboardView();
      break;
  }
  els.viewRoot.innerHTML = html;
  afterRender();
}

function afterRender() {
  if (section === 'billing') attachChartHover();
}

function updateUpdateCard() {
  if (!state || state.phase !== 'signedIn' || section !== 'settings') return;
  const host = document.getElementById('update-card-host');
  if (host) host.innerHTML = updateCardInner(state.update);
}

// -------------------------------------------------------------- primitives

function esc(value) {
  return String(value == null ? '' : value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function icon(name, className = 'icon') {
  return `<svg class="${className}" aria-hidden="true"><use href="#icon-${name}"></use></svg>`;
}

function pill(label, tint, withDot = true) {
  return `<span class="pill tint-${tint}${withDot ? '' : ' no-dot'}">${esc(label)}</span>`;
}

function currency(value) {
  return `¥${currencyFormatter.format(Number(value) || 0)}`;
}

function clamp01(value) {
  return Math.min(Math.max(Number(value) || 0, 0), 1);
}

function rgba(hex, alpha) {
  const value = hex.replace('#', '');
  const full = value.length === 3 ? value.split('').map((c) => c + c).join('') : value;
  const int = parseInt(full, 16);
  return `rgba(${(int >> 16) & 255}, ${(int >> 8) & 255}, ${int & 255}, ${alpha})`;
}

function formatBytes(bytes) {
  if (!bytes || bytes <= 0) return '—';
  const mb = bytes / (1024 * 1024);
  return mb >= 1 ? `${mb.toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
}

function formatSpeed(bytes) {
  if (!bytes || bytes <= 0) return '0 KB/s';
  const mb = bytes / (1024 * 1024);
  return mb >= 1 ? `${mb.toFixed(1)} MB/s` : `${Math.max(1, Math.round(bytes / 1024))} KB/s`;
}

function formatStorage(bytes) {
  if (bytes == null || !Number.isFinite(Number(bytes))) return '—';
  const gib = Math.max(0, Number(bytes)) / 1073741824;
  if (gib >= 1024) return `${(gib / 1024).toFixed(2)} TB`;
  if (gib >= 100) return `${gib.toFixed(0)} GB`;
  return `${gib.toFixed(1)} GB`;
}

function formatDateTime(iso) {
  if (!iso) return '—';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '—';
  return dateTimeFormatter.format(date);
}

function releaseSoon(countdown) {
  if (!countdown) return false;
  if (countdown === '已到期' || countdown === '今天') return true;
  const match = countdown.match(/^(\d+)\s*天后$/);
  return match ? Number(match[1]) <= 3 : false;
}

function emptyState(iconName, title, message, action = '') {
  return `<div class="empty">
    <div class="empty-icon">${icon(iconName)}</div>
    <h3>${esc(title)}</h3>
    <p>${esc(message)}</p>
    ${action}
  </div>`;
}

function pageHeader({ eyebrow, tint = '', date = '', title, badge = '', subtitle, actions = '' }) {
  const dateLine = date
    ? `<span class="hairline"></span><span class="date-label">${esc(date)}</span>`
    : '';
  return `<header class="page-header">
    <div>
      <div class="eyebrow-line"><span class="eyebrow ${tint ? `tint-${tint}` : ''}">${esc(eyebrow)}</span>${dateLine}</div>
      <div class="page-title-line"><h1 class="page-title">${esc(title)}</h1>${badge}</div>
      <p class="page-subtitle">${esc(subtitle)}</p>
    </div>
    <div class="header-actions">${actions}</div>
  </header>`;
}

function balanceChip() {
  const balance = state.balance;
  const low = Boolean(state.isLowBalance);
  const title = balance
    ? `现金 ${balance.formattedCash} · 代金券 ${balance.formattedVoucher} · 冻结 ${balance.formattedBlocked}`
    : '正在同步 AutoDL 账户余额';
  return `<div class="chip ${low ? 'is-warning' : ''}" title="${esc(title)}">
    ${icon(low ? 'alert' : 'wallet')}
    <div class="chip-copy">
      <span class="chip-label">可用余额</span>
      <span class="chip-value">${balance ? esc(balance.formattedAvailable) : '同步中'}</span>
    </div>
  </div>`;
}

function syncChip(busy, label) {
  const text = busy ? '同步中' : label || `${state.pollInterval}s 刷新`;
  return `<span class="status-chip ${busy ? 'is-busy' : ''}"><i class="dot"></i>${esc(text)}</span>`;
}

function iconButton(action, symbol, busy, title) {
  return `<button class="icon-btn ${busy ? 'is-busy' : ''}" type="button" data-action="${action}" title="${esc(
    title
  )}" aria-label="${esc(title)}">${icon(symbol)}</button>`;
}

// -------------------------------------------------------------------- auth

function authView() {
  const busy = Boolean(state.isLoggingIn) || state.phase === 'checking';
  const error = state.loginError;
  const loginWindowOpen = Boolean(state.loginWindowOpen);

  return `<div class="auth-view">
    <div class="auth-hero">
      <div class="auth-logo"><img src="../../assets/brand.png" alt="胡闹AutoDL" draggable="false" /></div>
      <div class="auth-kicker">GPU Sentinel · Local First</div>
      <h1 class="auth-title">把显卡，<br />守在手里。</h1>
      <p class="auth-lead">登录 AutoDL 后，胡闹AutoDL 会替你盯住实例状态与目标主机的空闲显卡。有卡就提醒，或者直接帮你开机抢下。</p>
      <ul class="auth-points">
        <li class="auth-point"><span class="point-icon">${icon('key')}</span><span>应用内完成 AutoDL 登录，自动读取登录凭证</span></li>
        <li class="auth-point"><span class="point-icon">${icon('scope')}</span><span>锁定目标主机，盯住空闲 GPU 与实例资源</span></li>
        <li class="auth-point"><span class="point-icon">${icon('bolt')}</span><span>有卡自动开机，或者只发送桌面通知</span></li>
      </ul>
    </div>

    <div class="auth-card">
      <span class="card-eyebrow tint-aqua">Connect Account</span>
      <h2>连接你的 AutoDL</h2>
      <p class="auth-desc">使用 AutoDL 账号登录。Token 只会保存在这台电脑上，不经由任何第三方服务器。</p>

      <button class="btn primary block" type="button" data-action="browser-login" ${busy ? 'disabled' : ''}>
        ${busy ? '<span class="spinner"></span>' : icon('google')}
        ${busy ? '正在验证账号…' : '浏览器授权（推荐）'}
      </button>
      <p class="auth-hint">会打开应用内登录窗口；登录成功后自动完成连接，无需复制粘贴 Token。</p>

      ${
        loginWindowOpen
          ? `<div class="update-checking"><span class="spinner"></span><span>登录窗口已打开，完成登录后会自动同步。</span></div>`
          : ''
      }

      <div class="divider">或使用 Token</div>

      <details class="token-details" ${error ? 'open' : ''}>
        <summary>手动填写 AutoDL Token</summary>
        <div class="token-body">
          <div class="field">
            ${icon('key')}
            <input id="token-input" type="password" placeholder="粘贴 AutoDL Token" autocomplete="off" spellcheck="false" ${busy ? 'disabled' : ''} />
          </div>
          <button class="btn block" type="button" data-action="manual-login" ${busy ? 'disabled' : ''}>连接 AutoDL</button>
          <p class="auth-hint">在 AutoDL 控制台「设置 → 开发者 Token」中获取。</p>
        </div>
      </details>

      ${error ? `<div class="auth-error">${esc(error)}</div>` : ''}

      <div class="auth-note">
        ${icon('shield')}
        <span>Token 仅保存在本机，Windows 上使用系统 DPAPI 加密；胡闹AutoDL 只通过 AutoDL 官方接口读取数据。</span>
      </div>
    </div>
  </div>`;
}

async function submitManualToken() {
  const input = document.getElementById('token-input');
  const value = input ? input.value.trim() : '';
  if (!value) {
    showToast({ kind: 'warning', title: '请填写 Token', message: '在 AutoDL 控制台获取 Token 后再连接。' });
    if (input) input.focus();
    return;
  }
  if (input) input.blur();
  try {
    const result = await window.hunao.signIn(value);
    if (result && !result.ok && result.error) {
      showToast({ kind: 'error', title: '连接失败', message: result.error });
    }
  } catch (error) {
    showToast({ kind: 'error', title: '连接失败', message: String(error && error.message ? error.message : error) });
  }
}

async function confirmLogout() {
  const confirmed = await window.hunao.confirm({
    title: '退出 AutoDL 登录',
    message: '确定要退出当前 AutoDL 账号吗？',
    detail: '退出后自动监控会暂停，保存在本机的 Token 会被删除。',
    confirmLabel: '退出登录',
    cancelLabel: '取消',
  });
  if (!confirmed) return;
  await window.hunao.logout();
  navigate('dashboard');
}

// --------------------------------------------------------------- dashboard

function dashboardView() {
  const selected = state.selectedInstance;
  const instances = state.instances || [];

  const actions = `
    ${balanceChip()}
    ${syncChip(state.isRefreshing)}
    ${iconButton('refresh', 'refresh', state.isRefreshing, '立即刷新')}
  `;

  return `<div class="page">
    ${pageHeader({
      eyebrow: 'Command Center',
      date: state.todayLabel,
      title: '监控台',
      badge: pill(instances.length === 0 ? '等待实例' : state.isRefreshing ? '同步中' : '实时监控', instances.length === 0 ? 'amber' : 'mint'),
      subtitle: '哎呀，这简直是胡！闹！',
      actions,
    })}
    ${state.lastError ? `<div class="banner">${icon('alert')}<span>${esc(state.lastError)}</span><button class="btn ghost sm" type="button" data-action="refresh">重试</button></div>` : ''}
    <div class="dash-top">
      ${sentinelCard()}
      <div class="side-stack">
        ${autoStartCard()}
        ${targetCard()}
      </div>
    </div>
    ${resourceDeck()}
    <div class="bottom-grid">
      ${activityCard()}
      ${guardCard()}
    </div>
  </div>`;
}

function sentinelCard() {
  const instance = state.selectedInstance;
  const stock = state.stock;
  const available = Boolean(stock && stock.isAvailable);

  return `<section class="card sentinel ${available ? 'glow-mint' : 'glow-aqua'}">
    <div class="sentinel-head">
      <div class="card-heading">
        <span class="card-eyebrow tint-aqua">Live GPU Monitor</span>
        <h2 class="card-title">GPU 空闲哨兵</h2>
      </div>
      ${instance ? pill(instance.stateLabel, instance.stateTint) : pill('未选择实例', 'muted')}
    </div>
    ${
      instance
        ? `<div class="sentinel-body">
            ${gpuGauge(instance)}
            <div class="sentinel-copy">
              <h3 class="sentinel-headline ${available ? 'is-live' : ''}">${esc(state.availabilityHeadline)}</h3>
              <div class="sentinel-target">
                <strong>${esc(instance.name)}</strong>
                <span class="sep"></span>
                <span>${esc(instance.gpuName)}</span>
              </div>
              <p class="sentinel-caption">${esc(state.availabilityCaption)}</p>
              <div class="sentinel-spacer"></div>
              <div class="meta-row">
                <span class="meta-chip">${icon('map-pin')}${esc(instance.displayRegion)}</span>
                <span class="meta-chip">${icon('server')}${esc(instance.machineLabel)}</span>
                <span class="meta-chip">${icon('bolt')}${esc(`${instance.gpuCount} 卡 · ${instance.chargeLabel}`)}</span>
                <span class="meta-chip">${icon('clock')}更新于 ${esc(state.lastUpdatedLabel || '尚未同步')}</span>
              </div>
            </div>
          </div>
          ${slotStrip(instance)}`
        : emptyState('instances', '还没有可监控的实例', '在 AutoDL 控制台创建实例后，这里会显示目标主机的空闲 GPU。', `<button class="btn primary sm" type="button" data-action="open-console">${icon('external')}打开 AutoDL 控制台</button>`)
    }
  </section>`;
}

function gpuGauge(instance) {
  const stock = state.stock;
  const total = stock ? stock.totalGPUs : null;
  const idle = stock ? stock.idleGPUs : null;
  const required = stock && stock.requiredGPUs ? stock.requiredGPUs : instance.gpuCount;
  const fraction = total ? clamp01(idle / total) : 0;
  const caption = stock ? (total == null ? '空闲 GPU' : `空闲 / 共 ${total} 张`) : '等待同步';
  const sub = `需 ${Math.max(required || 1, 1)} 张`;

  return `<div class="gpu-gauge">${ringSvg({
    id: 'gpu-ring',
    size: 156,
    radius: 62,
    fraction,
    value: idle == null ? '—' : String(idle),
    caption,
    sub,
    live: Boolean(stock && stock.isAvailable),
    gradient: ['#61fac2', '#54cfff'],
  })}</div>`;
}

function resourceGauge({ id, value, caption, sub, fraction, gradient, title }) {
  return `<div class="res-gauge" title="${esc(title || '')}">${ringSvg({
    id,
    size: 112,
    radius: 45,
    fraction,
    value,
    caption,
    sub,
    live: false,
    gradient,
  })}</div>`;
}

function ringSvg({ id, size, radius, fraction, value, caption, sub, live, gradient }) {
  const center = size / 2;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference * (1 - clamp01(fraction));
  const orbit = radius + (size > 130 ? 8 : 5);
  const dotY = center - orbit;
  return `<svg class="gauge-svg" viewBox="0 0 ${size} ${size}" aria-hidden="true">
      <defs>
        <linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="${gradient[0]}" />
          <stop offset="100%" stop-color="${gradient[1]}" />
        </linearGradient>
      </defs>
      <circle class="gauge-track" cx="${center}" cy="${center}" r="${radius}"></circle>
      <circle class="gauge-progress" cx="${center}" cy="${center}" r="${radius}" stroke="url(#${id})"
        stroke-dasharray="${circumference.toFixed(2)}" stroke-dashoffset="${offset.toFixed(2)}"
        transform="rotate(-90 ${center} ${center})"></circle>
      <circle class="gauge-orbit" cx="${center}" cy="${center}" r="${orbit}" style="stroke:${rgba(gradient[0], 0.24)}"></circle>
      <circle class="gauge-dot" cx="${center}" cy="${dotY}" r="${size > 130 ? 2.4 : 1.8}" style="fill:${gradient[0]}"></circle>
    </svg>
    <div class="gauge-center">
      <span class="gauge-value ${live ? 'is-live' : ''}">${esc(value)}</span>
      <span class="gauge-caption">${esc(caption)}</span>
      <span class="gauge-sub">${esc(sub)}</span>
    </div>`;
}

function slotStrip(instance) {
  const stock = state.stock;
  const slotCount = Math.min(Math.max((stock && stock.totalGPUs) || instance.gpuCount || 1, 1), 12);
  const idle = stock ? Math.min(stock.idleGPUs, slotCount) : 0;
  const slots = Array.from({ length: slotCount }, (_, index) => `<i class="slot ${stock && index < idle ? 'on' : ''}"></i>`).join('');
  return `<div class="slot-strip">
    <span class="slot-label">GPU SLOTS</span>
    <div class="slots">${slots}</div>
    <span class="slot-free ${stock ? '' : 'is-muted'}">${stock ? `${idle} FREE` : '待同步'}</span>
  </div>`;
}

function autoStartCard() {
  const enabled = state.autoStartEnabled;
  const subtitle = state.isAutoStarting ? '正在抢占空闲显卡…' : state.autoStartSubtitle;
  return `<section class="card mini-card ${enabled ? 'glow-mint' : ''}">
    <div class="mini-head">
      <div class="mini-icon ${enabled ? 'is-on' : ''}">${icon('power')}</div>
      <div class="mini-title-group">
        <span class="card-eyebrow ${enabled ? 'tint-mint' : ''}">${enabled ? 'Auto Pilot' : 'Manual Watch'}</span>
        <span class="mini-title">自动开机</span>
      </div>
      <div class="mini-head-right">
        <button class="switch ${enabled ? 'on' : ''}" type="button" data-action="toggle-auto-start" role="switch" aria-checked="${enabled}" aria-label="自动开机"></button>
      </div>
    </div>
    <p class="mini-sub">${esc(subtitle)}</p>
    <div class="mini-foot">
      <i class="dot ${enabled ? '' : 'amber'}"></i>
      <span>${enabled ? '空闲即抢，成功后通知我' : '关闭自动开机，有卡时提醒我'}</span>
    </div>
  </section>`;
}

function targetCard() {
  const selected = state.selectedInstance;
  const instances = state.instances || [];

  const options = instances
    .map((item) => `<option value="${esc(item.id)}" ${item.id === state.selectedInstanceId ? 'selected' : ''}>${esc(item.name)}</option>`)
    .join('');

  return `<section class="card mini-card glow-aqua">
    <div class="mini-head">
      <div class="mini-icon is-aqua">${icon('scope')}</div>
      <div class="mini-title-group">
        <span class="card-eyebrow tint-aqua">Active Target</span>
        <span class="mini-title">监控目标</span>
      </div>
      <div class="mini-head-right">
        ${
          instances.length
            ? `<select class="target-select" data-action="select-target" aria-label="切换监控目标">${options}</select>`
            : ''
        }
      </div>
    </div>
    ${
      selected
        ? `<p class="target-name">${esc(selected.name)}</p>
          <p class="target-meta">${esc(`${selected.gpuName} · ${selected.displayRegion}`)}</p>
          <p class="target-resource" title="${esc(`${selected.memoryDetailLabel} · ${selected.storageDetailLabel}`)}">内存剩余 ${esc(selected.memoryFreeLabel)} · 存储剩余 ${esc(selected.storageFreeLabel)}</p>
          <div class="target-bottom">
            <span class="mono" title="${esc(selected.machineLabel)}">${esc(selected.machineLabel)}</span>
            <button class="btn ghost sm" type="button" data-action="nav" data-section="instances">管理实例</button>
          </div>`
        : `<p class="target-name">等待选择</p>
          <p class="target-meta">前往 AutoDL 创建实例</p>
          <p class="target-resource">创建后刷新即可开始监控</p>
          <div class="target-bottom">
            <span class="mono">AutoDL 控制台</span>
            <button class="btn ghost sm" type="button" data-action="open-console">打开</button>
          </div>`
    }
  </section>`;
}

function resourceDeck() {
  const instance = state.selectedInstance;
  return `<section class="card resource-deck glow-violet">
    <div class="card-head">
      <div class="card-heading">
        <span class="card-eyebrow tint-violet">Runtime Resources</span>
        <h2 class="card-title">实例资源余量</h2>
      </div>
      ${instance ? pill(instance.stateLabel, instance.stateTint) : pill('未选择实例', 'muted')}
    </div>
    ${
      instance
        ? `<div class="resource-body">
            ${resourceGauge({
              id: 'memory-ring',
              value: instance.memoryFreeLabel,
              caption: '剩余内存',
              sub: instance.memoryTotalBytes != null ? `共 ${formatStorage(instance.memoryTotalBytes)}` : '待同步',
              fraction: instance.memoryUsedFraction == null ? 0 : 1 - instance.memoryUsedFraction,
              gradient: ['#9b85ff', '#54cfff'],
              title: instance.memoryDetailLabel,
            })}
            ${resourceGauge({
              id: 'storage-ring',
              value: instance.storageFreeLabel,
              caption: '剩余存储',
              sub: instance.storageTotalBytes != null ? `共 ${formatStorage(instance.storageTotalBytes)}` : '待同步',
              fraction: instance.storageUsedFraction == null ? 0 : 1 - instance.storageUsedFraction,
              gradient: ['#54cfff', '#61fac2'],
              title: instance.storageDetailLabel,
            })}
            <div class="res-divider"></div>
            <div class="res-details">
              <div class="detail-row">
                <span class="detail-icon violet">${icon('memory')}</span>
                <span class="detail-copy"><span>运行内存</span><strong>${esc(instance.memoryDetailLabel)}</strong></span>
              </div>
              <div class="detail-row">
                <span class="detail-icon aqua">${icon('storage')}</span>
                <span class="detail-copy"><span>磁盘空间</span><strong>${esc(instance.storageDetailLabel)}</strong></span>
              </div>
              <div class="res-foot">${icon('clock')}随每次刷新同步 · 每 ${state.pollInterval} 秒</div>
            </div>
          </div>`
        : emptyState('gauge', '暂无资源数据', '选择实例后，这里会显示内存与存储的圆形余量仪表。')
    }
  </section>`;
}

function activityCard() {
  const events = state.activity || [];
  const rows = events
    .map(
      (event) => `<div class="activity-item">
        <span class="activity-icon ${esc(event.kind)}">${icon(ACTIVITY_ICONS[event.kind] || 'info')}</span>
        <div class="activity-copy">
          <div class="activity-title">${esc(event.title)}</div>
          ${event.detail ? `<div class="activity-detail" title="${esc(event.detail)}">${esc(event.detail)}</div>` : ''}
        </div>
        <span class="activity-time">${esc(event.time)}</span>
      </div>`
    )
    .join('');

  return `<section class="card activity-card glow-violet">
    <div class="activity-head">
      <div class="card-heading">
        <span class="card-eyebrow tint-violet">Live Activity</span>
        <h2 class="card-title">实时动态</h2>
      </div>
      <span class="activity-count"><i class="dot"></i>${state.activityCount || 0} 条</span>
    </div>
    ${events.length ? `<div class="activity-list">${rows}</div>` : emptyState('dashboard', '还没有监控动态', '实例状态变化、空闲提醒和自动开机会记录在这里。')}
  </section>`;
}

function guardCard() {
  const balance = state.balance;
  const notificationTint = state.notificationsSupported ? 'mint' : 'rose';
  return `<section class="card guard-card glow-amber">
    <div class="guard-head">
      <div class="card-heading">
        <span class="card-eyebrow tint-amber">Guardrails</span>
        <h2 class="card-title">守护设置</h2>
      </div>
      ${icon('shield')}
    </div>
    <div class="guard-rows">
      <div class="guard-row">${icon('clock')}<span>检查频率</span><strong class="tint-violet">每 ${state.pollInterval} 秒</strong></div>
      <div class="guard-row">${icon('wallet')}<span>账户余额</span><strong class="${state.isLowBalance ? 'tint-amber' : 'tint-mint'}">${
        balance ? `${esc(balance.formattedAvailable)}${state.isLowBalance ? ' · 偏低' : ''}` : '同步中'
      }</strong></div>
      <div class="guard-row">${icon('bell')}<span>系统通知</span><strong class="tint-${notificationTint}">${state.notificationsSupported ? '可用' : '不可用'}</strong></div>
      <div class="guard-row">${icon('key')}<span>登录凭证</span><strong class="tint-mint">已存入本机</strong></div>
    </div>
    <button class="btn ghost sm" type="button" data-action="nav" data-section="settings">调整守护参数</button>
  </section>`;
}

// --------------------------------------------------------------- instances

function instancesView() {
  const instances = state.instances || [];
  const selectedName = state.selectedInstance ? state.selectedInstance.name : '未选择';
  const actions = `
    ${syncChip(state.isRefreshing)}
    ${iconButton('refresh', 'refresh', state.isRefreshing, '刷新实例')}
    <button class="btn ghost sm" type="button" data-action="open-console">${icon('external')}AutoDL 控制台</button>
  `;

  const stats = `<div class="stat-strip">
    ${statCard('instances', '全部实例', String(instances.length), '台', 'aqua')}
    ${statCard('bolt', '运行中', String(state.runningCount || 0), '台', 'mint')}
    ${statCard('scope', '监控目标', selectedName, '', 'violet', 'is-name')}
    ${statCard('power', '自动开机', state.autoStartEnabled ? '已开启' : '已关闭', '', 'mint', 'is-name')}
  </div>`;

  return `<div class="page">
    ${pageHeader({
      eyebrow: 'Instance Fleet',
      tint: 'aqua',
      title: '我的实例',
      badge: pill(`${instances.length} 台`, 'aqua'),
      subtitle: '查看所有实例状态，或切换胡闹AutoDL 的监控目标。',
      actions,
    })}
    ${stats}
    ${
      instances.length
        ? `<div class="instance-list">${instances.map(instanceCard).join('')}</div>`
        : `<section class="card">${emptyState(
            'instances',
            '账号下还没有实例',
            '去 AutoDL 创建一台 GPU 实例，然后回来刷新。胡闹AutoDL 只负责替你盯着它。',
            `<button class="btn primary sm" type="button" data-action="open-console">${icon('external')}打开 AutoDL 控制台</button>`
          )}</section>`
    }
  </div>`;
}

function statCard(symbol, label, value, suffix, tint, extraClass = '') {
  return `<div class="card stat-card">
    <div class="stat-icon ${tint}">${icon(symbol)}</div>
    <div class="stat-copy">
      <span class="stat-label">${esc(label)}</span>
      <span class="stat-value ${extraClass}" title="${esc(value)}">${esc(value)}${suffix ? `<small>${esc(suffix)}</small>` : ''}</span>
    </div>
  </div>`;
}

function instanceCard(instance) {
  const isTarget = instance.id === state.selectedInstanceId;
  const acting = state.actionInstanceId === instance.id;
  const blocked = acting || ['starting', 'stopping', 'unknown'].includes(instance.state);
  const running = instance.state === 'running';
  const soon = releaseSoon(instance.releaseCountdown);

  const powerButton = `<button class="btn ${running ? 'danger' : 'primary'}" type="button" data-action="${
    running ? 'power-off' : 'power-on'
  }" data-id="${esc(instance.id)}" ${blocked ? 'disabled' : ''} title="${esc(
    blocked ? '实例状态处理中，请稍候' : running ? '关闭实例（会先确认）' : '启动实例'
  )}">
    ${blocked && acting ? '<span class="spinner"></span>' : icon(running ? 'stop' : 'play')}
    ${blocked && acting ? '处理中' : running ? '关机' : '开机'}
  </button>`;

  const links = [
    instance.sshCommand
      ? `<button class="chip-link" type="button" data-action="copy-ssh" data-value="${esc(instance.sshCommand)}" title="${esc(instance.sshCommand)}">${icon('copy')}复制 SSH</button>`
      : '',
    instance.jupyterDomain
      ? `<button class="chip-link" type="button" data-action="open-jupyter" data-url="${esc(jupyterUrl(instance.jupyterDomain))}" title="在浏览器中打开 Jupyter">${icon('external')}Jupyter</button>`
      : '',
    `<button class="chip-link" type="button" data-action="open-instance-console">${icon('external')}控制台</button>`,
  ]
    .filter(Boolean)
    .join('');

  return `<article class="card instance-card ${isTarget ? 'is-target' : ''}">
    <div class="instance-icon tint-${instance.stateTint} ${isTarget ? 'scope-mark' : ''}">${icon('server')}</div>
    <div class="instance-main">
      <div class="instance-title-row">
        <h3 title="${esc(instance.name)}">${esc(instance.name)}</h3>
        ${pill(instance.stateLabel, instance.stateTint)}
        ${isTarget ? pill('监控目标', 'mint', false) : ''}
        ${instance.startedLabel ? `<span class="instance-meta" style="margin-left:auto">${icon('play')}启动于 ${esc(instance.startedLabel)}</span>` : ''}
      </div>
      <div class="instance-meta">
        <span>${icon('bolt')}${esc(`${instance.gpuName} × ${instance.gpuCount}`)}</span>
        <span>${icon('map-pin')}${esc(instance.displayRegion)}</span>
        <span>${icon('server')}${esc(instance.machineLabel)}</span>
        <span title="${esc(instance.storageDetailLabel)}">${icon('storage')}剩余 ${esc(instance.storageFreeLabel)}</span>
        <span title="${esc(instance.memoryDetailLabel)}">${icon('memory')}内存剩余 ${esc(instance.memoryFreeLabel)}</span>
      </div>
      <div class="instance-meta">
        <span class="${soon ? 'release-soon' : ''}" title="${esc(instance.releaseDetail)}">${icon('clock')}释放时间 ${esc(instance.releaseLabel)}${
          instance.releaseCountdown ? ` · ${esc(instance.releaseCountdown)}` : ''
        }</span>
        <span>${icon('wallet')}${esc(instance.chargeLabel)}</span>
        <span>${icon('key')}${esc(instance.shortID)}</span>
      </div>
      <div class="instance-links">${links}</div>
    </div>
    <div class="instance-actions">
      ${!isTarget ? `<button class="btn ghost" type="button" data-action="select-target" data-id="${esc(instance.id)}">${icon('scope')}设为目标</button>` : ''}
      <button class="btn ghost" type="button" data-action="open-instance-console" title="打开 AutoDL 控制台，在网页中手动确认释放">${icon('trash')}释放</button>
      ${powerButton}
    </div>
  </article>`;
}

function jupyterUrl(domain) {
  if (!domain) return '';
  return /^https?:\/\//i.test(domain) ? domain : `https://${domain}`;
}

function copyValue(value, successTitle) {
  if (!value) {
    showToast({ kind: 'warning', title: '暂无可复制内容', message: 'AutoDL 还没有返回这条信息。' });
    return;
  }
  window.hunao.copyText(value);
  showToast({ kind: 'success', title: successTitle, message: value });
}

function openJupyter(url) {
  if (!url) return;
  window.hunao.openExternal(url);
}

async function confirmPowerOff(id) {
  const instance = (state.instances || []).find((item) => item.id === id);
  if (!instance) return;
  if (instance.state !== 'running') {
    window.hunao.powerOff(id);
    return;
  }
  const confirmed = await window.hunao.confirm({
    title: '关闭实例？',
    message: `确定要关闭「${instance.name}」吗？`,
    detail: state.autoStartEnabled
      ? '自动开机已开启，检测到空闲显卡后胡闹AutoDL 会再次帮你开机。'
      : '关闭后实例将停止计费，但当前训练任务也会中止。',
    confirmLabel: '关机',
    cancelLabel: '取消',
  });
  if (confirmed) window.hunao.powerOff(id);
}

// ----------------------------------------------------------------- billing

function billingView() {
  const snapshot = state.billing;
  const busy = state.isBillingLoading;
  const actions = `
    ${snapshot ? `<span class="status-chip" title="账单同步时间"><i class="dot"></i>同步于 ${esc(snapshot.fetchedLabel)}</span>` : ''}
    <button class="btn ghost sm" type="button" data-action="open-billing-console">${icon('external')}完整账单</button>
    ${iconButton('billing-refresh', 'refresh', busy, '刷新账单')}
  `;

  let body = '';
  if (snapshot) {
    body = `${billingSummary(snapshot)}
      ${
        snapshot.recordCount === 0
          ? `<section class="card">${emptyState('billing', '暂无账单流水', '实例产生消费后，这里会显示每日消费与 GPU 构成。')}</section>`
          : `${chartCard(snapshot)}
            <div class="billing-bottom">
              ${compositionCard(snapshot)}
              ${billsCard(snapshot)}
            </div>`
      }`;
  } else if (state.billingError) {
    body = `<section class="card billing-error">
      ${icon('alert')}
      <h3>账单同步失败</h3>
      <p>${esc(state.billingError)}</p>
      <button class="btn" type="button" data-action="billing-refresh">${icon('refresh')}重新同步</button>
    </section>`;
  } else {
    body = `<section class="card loading-card"><span class="spinner"></span><span>正在同步 AutoDL 账单…</span></section>`;
  }

  return `<div class="page">
    ${pageHeader({
      eyebrow: 'Billing Ledger',
      tint: 'amber',
      title: '账单',
      badge: pill(snapshot ? `近 ${billingRange} 天` : '同步中', snapshot ? 'amber' : 'muted'),
      subtitle: '每一度电、每一张卡，都算得明明白白。',
      actions,
    })}
    ${state.billingError && snapshot ? `<div class="banner">${icon('alert')}<span>${esc(state.billingError)}</span><button class="btn ghost sm" type="button" data-action="billing-refresh">重试</button></div>` : ''}
    ${body}
  </div>`;
}

function billingSummary(snapshot) {
  const summary = snapshot.summary || {};
  const days = snapshot.series30.slice(-billingRange);
  const total = days.reduce((sum, day) => sum + day.amount, 0);
  const average = days.length ? total / days.length : 0;
  const daysRemaining = summary.daysRemaining;
  const totalClass = total > 0 ? 'grad-text' : '';

  return `<div class="billing-summary">
    <section class="card spend-card glow-mint">
      <div class="spend-head">
        <div class="card-heading">
          <span class="card-eyebrow tint-mint">Spending Pulse</span>
          <h2 class="card-title">近 ${billingRange} 天消费</h2>
        </div>
        <span class="spend-average">${icon('billing')}日均 ${currency(average)}</span>
      </div>
      <div class="spend-total ${totalClass}">${currency(total)}</div>
      <div class="spend-stats">
        ${spendStat('今日', currency(summary.today), 'aqua')}
        ${spendStat('近 7 天', currency(summary.last7), 'mint')}
        ${spendStat('本月', currency(summary.month), 'violet')}
        ${spendStat(
          '余额可撑',
          daysRemaining == null ? '—' : `${daysRemaining} 天`,
          daysRemaining == null ? 'muted' : daysRemaining < 7 ? 'rose' : 'amber',
          '按最近 7 天的日均消费估算'
        )}
      </div>
    </section>
    ${walletCard(snapshot)}
  </div>`;
}

function spendStat(label, value, tint, help = '') {
  return `<div class="spend-stat" title="${esc(help)}"><span>${esc(label)}</span><strong class="${tint}">${esc(value)}</strong></div>`;
}

function walletCard() {
  const balance = state.balance;
  const cash = Math.max((balance && balance.cash) || 0, 0);
  const voucher = Math.max((balance && balance.voucher) || 0, 0);
  const blocked = Math.max((balance && balance.blocked) || 0, 0);
  const total = cash + voucher + blocked;

  const segment = (value, kind) =>
    total > 0 && value > 0 ? `<i class="${kind}" style="width:${(value / total) * 100}%"></i>` : '';

  return `<section class="card wallet-card glow-aqua">
    <div class="card-head">
      <div class="card-heading">
        <span class="card-eyebrow tint-aqua">Wallet</span>
        <h2 class="card-title">账户余额</h2>
      </div>
      ${icon('wallet')}
    </div>
    <div class="wallet-value">${balance ? esc(balance.formattedAvailable) : '同步中'}</div>
    <div class="wallet-label">${balance ? '现金 + 代金券可用' : '正在同步钱包'}</div>
    <div class="wallet-bar">
      ${segment(cash, 'cash')}${segment(voucher, 'voucher')}${segment(blocked, 'blocked')}
    </div>
    <div class="wallet-legend">
      <span><i class="legend-dot" style="background:var(--mint)"></i>现金<strong>${balance ? esc(balance.formattedCash) : '—'}</strong></span>
      <span><i class="legend-dot" style="background:var(--aqua)"></i>代金券<strong>${balance ? esc(balance.formattedVoucher) : '—'}</strong></span>
      <span><i class="legend-dot" style="background:rgba(255,194,87,0.7)"></i>冻结<strong>${balance ? esc(balance.formattedBlocked) : '—'}</strong></span>
    </div>
  </section>`;
}

function chartCard(snapshot) {
  const days = snapshot.series30.slice(-billingRange);
  const total = days.reduce((sum, day) => sum + day.amount, 0);
  const average = days.length ? total / days.length : 0;
  const max = Math.max(...days.map((day) => day.amount), 1);
  const scale = max * 1.12;
  const gap = days.length > 14 ? '3px' : '6px';
  const last = days[days.length - 1] || null;

  const bars = days
    .map(
      (day, index) => `<div class="chart-bar ${day.isToday ? 'today' : ''}" data-index="${index}"
        data-label="${esc(day.label)}" data-amount="${esc(currency(day.amount))}">
        <i style="--bar-height:${((day.amount / scale) * 100).toFixed(2)}%"></i>
      </div>`
    )
    .join('');

  const labels = days
    .map((day, index) => {
      const visible = days.length <= 14 || index % 5 === 0 || index === days.length - 1;
      return `<span class="${day.isToday ? 'today' : ''}">${visible ? esc(day.label) : ''}</span>`;
    })
    .join('');

  const grid = [0, 25, 50, 75]
    .map((top) => `<i style="top:${top}%"></i>`)
    .join('');

  return `<section class="card chart-card glow-aqua">
    <div class="chart-head">
      <div class="card-heading">
        <span class="card-eyebrow tint-aqua">Daily Burn</span>
        <h2 class="card-title">每日消费</h2>
      </div>
      <span class="chart-hover" id="chart-hover">
        <span>${esc(last ? last.label : '—')}</span><strong>${currency(last ? last.amount : 0)}</strong>
      </span>
      <div class="range-toggle">
        <button type="button" class="${billingRange === 14 ? 'active' : ''}" data-action="set-range" data-range="14">14 天</button>
        <button type="button" class="${billingRange === 30 ? 'active' : ''}" data-action="set-range" data-range="30">30 天</button>
      </div>
    </div>
    <div class="chart-area" id="billing-chart">
      <div class="chart-grid">${grid}</div>
      <div class="chart-average" style="bottom:${((average / scale) * 100).toFixed(2)}%">区间日均 ${currency(average)}</div>
      <div class="chart-bars" style="--chart-gap:${gap}">${bars}</div>
    </div>
    <div class="chart-labels" style="--chart-gap:${gap}">${labels}</div>
    <div class="chart-foot">
      <span class="chart-legend"><i class="dot"></i>每日消费<i class="line"></i>区间日均线 ${currency(average)}</span>
      <span>悬停柱形查看当日金额 · 单位：元</span>
    </div>
  </section>`;
}

function compositionCard(snapshot) {
  const slices = (snapshot.gpuSlices || []).slice(0, 5);
  const total = slices.reduce((sum, slice) => sum + slice.amount, 0);

  const bar = slices
    .map((slice, index) => `<i style="width:${Math.max(2, (slice.amount / Math.max(total, 0.01)) * 100)}%;background:${PALETTE[index % PALETTE.length]}"></i>`)
    .join('');

  const rows = slices
    .map(
      (slice, index) => `<div class="slice-row">
        <i class="slice-dot" style="background:${PALETTE[index % PALETTE.length]}"></i>
        <span class="slice-label" title="${esc(slice.label)}">${esc(slice.label)}</span>
        <span class="slice-percent">${slice.percent}%</span>
        <span class="slice-amount">${currency(slice.amount)}</span>
      </div>`
    )
    .join('');

  return `<section class="card composition-card glow-violet">
    <div class="card-head">
      <div class="card-heading">
        <span class="card-eyebrow tint-violet">Where It Goes</span>
        <h2 class="card-title">消费构成</h2>
      </div>
      <span class="composition-tag">近 30 天</span>
    </div>
    ${
      slices.length
        ? `<div class="slice-bar">${bar}</div>
          <div class="slice-rows">${rows}</div>
          <div class="composition-foot">${icon('bolt')}共 ${snapshot.chargeCount} 笔消费流水 · 按 GPU 型号统计</div>`
        : emptyState('billing', '暂无消费构成', '实例产生消费后，这里会按 GPU 型号拆分。')
    }
  </section>`;
}

function billsCard(snapshot) {
  const bills = snapshot.recent || [];
  const rows = bills
    .map(
      (bill) => `<div class="bill-row" title="${esc(bill.detailHelp || bill.subtitle)}">
        <span class="bill-icon tint-${bill.tint}">${icon(bill.symbol || 'bolt')}</span>
        <div class="bill-copy">
          <div class="bill-title-row">
            <strong title="${esc(bill.title)}">${esc(bill.title)}</strong>
            ${bill.discountLabel ? `<span class="bill-saving">${esc(bill.discountLabel)}</span>` : ''}
          </div>
          <div class="bill-sub">${esc(bill.subtitle)}</div>
        </div>
        <span class="bill-amount ${bill.isOutflow ? 'outflow' : 'inflow'}">${esc(bill.signedAmountLabel)}</span>
      </div>`
    )
    .join('');

  return `<section class="card bills-card glow-amber">
    <div class="bills-head">
      <div class="card-heading">
        <span class="card-eyebrow tint-amber">Recent Ledger</span>
        <h2 class="card-title">最近账单</h2>
      </div>
      <button class="btn ghost sm" type="button" data-action="open-billing-console">全部 ${icon('chevron-right')}</button>
    </div>
    ${bills.length ? `<div class="bills-list">${rows}</div>` : emptyState('billing', '暂无账单', '同步完成后这里会显示最近的消费流水。')}
  </section>`;
}

function setBillingRange(value) {
  if (![14, 30].includes(value) || value === billingRange) return;
  billingRange = value;
  renderView();
}

function attachChartHover() {
  const chart = document.getElementById('billing-chart');
  if (!chart) return;
  const bars = chart.querySelectorAll('.chart-bar');
  const last = bars[bars.length - 1];
  chart.addEventListener('mouseover', (event) => {
    const bar = event.target.closest('.chart-bar');
    if (!bar) return;
    updateChartHover(bar.dataset.label, bar.dataset.amount);
  });
  chart.addEventListener('mouseleave', () => {
    if (last) updateChartHover(last.dataset.label, last.dataset.amount);
  });
}

function updateChartHover(label, amount) {
  const hover = document.getElementById('chart-hover');
  if (!hover) return;
  hover.innerHTML = `<span>${esc(label)}</span><strong>${esc(amount)}</strong>`;
}

// ---------------------------------------------------------------- settings

function settingsView() {
  const update = state.update;
  const actions = `<span class="version-pill">v${esc(state.version || '1.2.0')}</span>
    <button class="btn ghost sm" type="button" data-action="open-repo">${icon('star', 'icon star-fill')}GitHub</button>`;

  return `<div class="page">
    ${pageHeader({
      eyebrow: 'Preferences',
      tint: 'violet',
      title: '设置',
      badge: pill(state.isDemo ? '演示模式' : '本地守护', state.isDemo ? 'amber' : 'mint'),
      subtitle: '调整检查节奏、通知方式、应用更新与账户连接。',
      actions,
    })}
    <div class="settings-grid">
      <section class="card update-card span-2" id="update-card-host">${updateCardInner(update)}</section>
      ${monitoringCard()}
      ${accountCard()}
      ${aboutCard()}
    </div>
  </div>`;
}

function updateCardInner(update) {
  const u = update || {};
  const phase = u.phase || 'idle';
  const release = u.release || null;
  const failed = phase === 'failed';
  const ready = phase === 'readyToInstall';
  const progress = phase === 'downloading' ? clamp01(u.progress) : ready ? 1 : 0;
  const percent = Math.round(progress * 100);
  const sideSymbol =
    failed ? 'alert' : phase === 'upToDate' ? 'check' : ready || phase === 'available' ? 'download' : 'refresh';
  const showNotes = Boolean(release) && ['available', 'downloading', 'readyToInstall', 'installing', 'failed'].includes(phase);
  const showProgress = ['downloading', 'readyToInstall', 'installing'].includes(phase);
  const showStar = Boolean(release) && ['available', 'downloading', 'readyToInstall', 'installing', 'failed'].includes(phase);

  return `<div class="update-top">
      <div class="update-main">
        <span class="card-eyebrow tint-mint">Updates</span>
        <div class="update-title-row">
          <h2>版本更新</h2>
          <span class="version-pill">当前 v${esc(u.currentVersion || state.version || '1.2.0')}</span>
          ${phase === 'upToDate' ? '<span class="update-badge"><i class="dot"></i>已是最新</span>' : ''}
          ${failed ? `<span class="update-badge" style="color:var(--rose)"><i class="dot" style="background:var(--rose)"></i>需要处理</span>` : ''}
        </div>
        <p class="update-sub"><strong style="color:var(--text-2);font-weight:600">${esc(updateHeadline(u))}</strong><br />${esc(
          updateSubtitle(u)
        )}</p>
        <div class="update-actions">${updateActions(u)}</div>
        <div class="update-meta-row">
          <span>${icon('shield')}安装包完整性自动校验</span>
          <span>${icon('clock')}${u.lastCheckedLabel ? `检查于 ${esc(u.lastCheckedLabel)}` : '尚未检查'}</span>
          <span>${icon('github')}GitHub Releases</span>
          ${u.isDemo ? `<span>${icon('info')}演示模式不请求网络</span>` : ''}
          ${u.supported === false ? `<span>${icon('info')}仅安装版支持应用内更新</span>` : ''}
        </div>
      </div>
      <div class="update-side ${failed ? 'is-amber' : ''}">${icon(sideSymbol)}</div>
    </div>
    ${showNotes ? releaseNotes(release) : ''}
    ${
      showProgress
        ? `<div class="update-progress">
            <div class="progress-head">
              <span>${phase === 'downloading' ? '下载进度' : phase === 'readyToInstall' ? '安装包已就绪' : '正在替换应用'}</span>
              <strong>${phase === 'downloading' ? `${percent}%` : phase === 'readyToInstall' ? '100%' : '即将重启'}</strong>
            </div>
            <div class="progress-track"><div class="progress-fill" style="width:${phase === 'installing' ? 100 : percent}%"></div></div>
            <div class="progress-meta">
              <span>${esc(progressFootnote(u, release, phase))}</span>
              <span>${u.lastCheckedLabel ? `检查于 ${esc(u.lastCheckedLabel)}` : ''}</span>
            </div>
          </div>`
        : ''
    }
    ${failed && u.error ? `<div class="update-error">${esc(u.error)}</div>` : ''}
    ${
      showStar
        ? `<div class="star-banner">
            <span class="star-banner-icon">${icon('star', 'icon star-fill')}</span>
            <div class="star-banner-copy">
              <strong>${esc(starHeadline(phase))}</strong><br />
              <span style="font-size:8.5px;color:var(--text-3)">开源免费 · 每颗 Star 都是作者 A2ureeE 持续更新的动力</span>
            </div>
            <button class="btn primary sm" type="button" data-action="open-repo">${icon('star', 'icon star-fill')}点个 Star</button>
          </div>`
        : ''
    }`;
}

function releaseNotes(release) {
  const notes = (release.notes || '').trim();
  const asset = release.assetName ? ` · ${release.assetName}` : '';
  return `<div class="release-notes" title="${esc(release.assetName || '')}">${esc(
    `v${release.version} 更新内容${asset}\n\n${notes || '本次更新暂无详细说明。'}`
  )}</div>`;
}

function updateHeadline(u) {
  switch (u.phase) {
    case 'checking':
      return '正在检查新版本…';
    case 'upToDate':
      return '已是最新版本';
    case 'available':
      return `发现新版本 v${u.release ? u.release.version : ''}`;
    case 'downloading':
      return `正在下载 v${u.release ? u.release.version : ''}`;
    case 'readyToInstall':
      return '更新已就绪，等待重启';
    case 'installing':
      return '正在安装更新…';
    case 'failed':
      return '更新未完成';
    default:
      return '更新检测已就绪';
  }
}

function updateSubtitle(u) {
  if (u.isDemo) {
    if (u.phase === 'idle' || u.phase === 'upToDate') return '演示模式不会请求 GitHub 检查更新。';
  }
  if (u.supported === false && (u.phase === 'idle' || u.phase === 'upToDate')) {
    return '应用内更新仅在打包后的安装版中可用。';
  }
  switch (u.phase) {
    case 'checking':
      return '正在连接 GitHub Releases 获取最新版本信息。';
    case 'upToDate':
      return `当前 v${u.currentVersion} 已是最新版本${
        u.lastCheckedLabel ? ` · 检查于 ${u.lastCheckedLabel}` : ''
      }。`;
    case 'available':
      return '下载、校验和安装都在应用内完成，无需打开 GitHub。';
    case 'downloading':
      return '下载完成后会校验安装包完整性，再提示你重启安装。';
    case 'readyToInstall':
      return '安装包已下载完成，重启后会替换旧版本并自动重新打开。';
    case 'installing':
      return '胡闹AutoDL 即将退出，更新完成后会自动重新启动。';
    case 'failed':
      return '可以重试，或前往 GitHub 发布页手动下载安装包。';
    default:
      return '每 24 小时自动检查一次，也可以随时手动检查。';
  }
}

function updateActions(u) {
  const releaseButton = u.release
    ? `<button class="btn ghost sm" type="button" data-action="release-page">${icon('external')}发布页</button>`
    : '';

  switch (u.phase) {
    case 'checking':
      return `<span class="update-badge"><span class="spinner"></span>检查中…</span>${releaseButton}`;
    case 'downloading':
      return `<span class="update-badge"><span class="spinner"></span>下载中 ${Math.round(clamp01(u.progress) * 100)}%</span>${releaseButton}`;
    case 'installing':
      return `<span class="update-badge"><span class="spinner"></span>即将重启…</span>`;
    case 'available':
      return `<button class="btn primary sm" type="button" data-action="update-download">${icon('download')}下载更新</button>${releaseButton}`;
    case 'readyToInstall':
      return `<button class="btn primary sm" type="button" data-action="update-install">${icon('refresh')}重启并安装</button>${releaseButton}`;
    case 'failed':
      return u.release
        ? `<button class="btn primary sm" type="button" data-action="update-download">${icon('refresh')}重新下载</button>${releaseButton}`
        : `<button class="btn primary sm" type="button" data-action="update-check">${icon('refresh')}重新检查</button>`;
    default:
      return `<button class="btn sm" type="button" data-action="update-check">${icon('refresh')}检查更新</button>${releaseButton}`;
  }
}

function progressFootnote(u, release, phase) {
  if (phase === 'downloading') {
    return `${formatBytes(u.transferred)} / ${formatBytes(u.total)} · ${formatSpeed(u.bytesPerSecond)} · 安装包仅保存到本机`;
  }
  if (phase === 'readyToInstall') {
    return `${(release && release.sizeLabel) || formatBytes(u.total)} · 已通过完整性校验 · 重启后替换当前应用`;
  }
  return '应用退出后自动完成安装并重新启动';
}

function starHeadline(phase) {
  switch (phase) {
    case 'available':
      return '发现新版本，顺手给胡闹AutoDL 点个 Star 吧';
    case 'downloading':
      return '更新下载中，点个 Star 支持作者';
    case 'readyToInstall':
      return '更新已就绪，点个 Star 再重启';
    case 'installing':
      return '正在安装更新，感谢你的 Star';
    case 'failed':
      return '更新遇到问题，也可以去 GitHub 看看';
    default:
      return '喜欢胡闹AutoDL？去 GitHub 点个 Star 吧';
  }
}

function openReleasePage() {
  const release = state && state.update && state.update.release;
  if (release && release.pageURL) {
    window.hunao.openExternal(release.pageURL);
    return;
  }
  window.hunao.openExternal(`${REPO_URL}/releases`);
}

function monitoringCard() {
  const interval = Number(state.pollInterval) || 15;
  const fill = ((interval - 8) / 112) * 100;
  return `<section class="card settings-card glow-violet">
    <div class="settings-card-head">
      <div class="card-heading">
        <span class="card-eyebrow tint-violet">Automation</span>
        <h2 class="card-title">守护参数</h2>
      </div>
      ${icon('settings')}
    </div>
    <div class="setting-row">
      <div class="setting-copy">
        <h3>自动开机</h3>
        <p>检测到目标主机有空闲显卡时，自动为你开机抢卡。</p>
      </div>
      <div class="setting-control">
        <button class="switch ${state.autoStartEnabled ? 'on' : ''}" type="button" data-action="toggle-auto-start" role="switch" aria-checked="${state.autoStartEnabled}" aria-label="自动开机"></button>
      </div>
    </div>
    <div class="setting-row">
      <div class="setting-copy">
        <h3>检查频率</h3>
        <p>每 ${interval} 秒拉取一次实例状态与显卡余量（8–120 秒）。</p>
      </div>
      <div class="setting-control">
        <div class="range-wrap">
          <input id="poll-range" type="range" min="8" max="120" step="1" value="${interval}" style="--fill:${fill}%" aria-label="检查频率" />
          <span class="range-value" id="poll-value">${interval} 秒</span>
        </div>
      </div>
    </div>
    <div class="setting-row">
      <div class="setting-copy">
        <h3>余额提醒阈值</h3>
        <p>可用余额低于该值时，发送系统通知提醒充值。</p>
      </div>
      <div class="setting-control">
        <div class="number-field">
          <span>¥</span>
          <input id="low-balance-input" type="number" min="1" max="10000" step="1" value="${Number(state.lowBalanceThreshold) || 20}" aria-label="余额提醒阈值" />
        </div>
        <button class="btn ghost sm" type="button" data-action="save-low-balance">保存</button>
      </div>
    </div>
    <div class="setting-row">
      <div class="setting-copy">
        <h3>测试通知</h3>
        <p>发一条桌面通知，确认 Windows 通知通道正常。</p>
      </div>
      <div class="setting-control">
        <button class="btn sm" type="button" data-action="test-notification" ${state.notificationsSupported ? '' : 'disabled'}>${icon('bell')}发送测试通知</button>
      </div>
    </div>
  </section>`;
}

function accountCard() {
  const hint = state.tokenHint || '—';
  return `<section class="card settings-card glow-aqua">
    <div class="settings-card-head">
      <div class="card-heading">
        <span class="card-eyebrow tint-aqua">Account</span>
        <h2 class="card-title">账户与凭证</h2>
      </div>
      ${icon('key')}
    </div>
    <div class="account-row">${icon('key')}<span>登录凭证</span><strong>${esc(hint)}</strong></div>
    <div class="account-row">${icon('clock')}<span>登录时间</span><strong>${esc(formatDateTime(state.signedInAt))}</strong></div>
    <div class="account-row">${icon('instances')}<span>实例数量</span><strong>${(state.instances || []).length} 台</strong></div>
    <div class="account-row">${icon('shield')}<span>凭证存储</span><strong>${state.isDemo ? '演示数据' : '本机 DPAPI 加密'}</strong></div>
    <div class="account-row">${icon('scope')}<span>应用内更新</span><strong>${state.update && state.update.supported ? '已启用' : '安装版可用'}</strong></div>
    <div style="margin-top:14px">
      <button class="btn danger block" type="button" data-action="logout">${icon('logout')}退出 AutoDL 登录</button>
    </div>
  </section>`;
}

function aboutCard() {
  return `<section class="card settings-card span-2">
    <div class="settings-card-head">
      <div class="card-heading">
        <span class="card-eyebrow tint-aqua">About</span>
        <h2 class="card-title">关于胡闹AutoDL</h2>
      </div>
      ${icon('info')}
    </div>
    <div class="account-row">${icon('github')}<span>作者</span><strong>A2ureeE</strong></div>
    <div class="account-row">${icon('download')}<span>版本</span><strong>v${esc(state.version || '1.2.0')} · Windows</strong></div>
    <div class="account-row">${icon('shield')}<span>数据来源</span><strong>AutoDL 官方接口</strong></div>
    <div class="about-links">
      <button class="btn ghost sm" type="button" data-action="open-repo">${icon('github')}GitHub 仓库</button>
      <button class="btn ghost sm" type="button" data-action="open-releases">${icon('download')}发布页</button>
      <button class="btn ghost sm" type="button" data-action="open-author">${icon('external')}作者主页</button>
      <button class="btn primary sm" type="button" data-action="open-repo">${icon('star', 'icon star-fill')}点个 Star</button>
    </div>
    <p class="about-note">胡闹AutoDL 仅通过 AutoDL 官方接口读取实例、显卡与账单数据。Token 保存在本机（Windows 使用 DPAPI 加密），不会上传到第三方服务器。自动开机需要应用保持运行，关闭窗口后会继续驻留在系统托盘。</p>
  </section>`;
}

async function saveLowBalance() {
  const input = document.getElementById('low-balance-input');
  if (!input) return;
  const value = Number(input.value);
  if (!Number.isFinite(value) || value < 1 || value > 10000) {
    showToast({ kind: 'warning', title: '阈值无效', message: '请输入 1 到 10000 之间的金额。' });
    input.focus();
    return;
  }
  await window.hunao.setLowBalanceThreshold(value);
  showToast({ kind: 'success', title: '余额提醒已更新', message: `可用余额低于 ${currency(value)} 时提醒你。` });
}

// ------------------------------------------------------------------ toasts

function showToast(toast) {
  if (!toast || !toast.title) return;
  const kind = ['success', 'warning', 'error'].includes(toast.kind) ? toast.kind : 'info';

  while (els.toastRoot.children.length >= 4) {
    els.toastRoot.firstElementChild.remove();
  }

  const element = document.createElement('div');
  element.className = `toast ${kind}`;
  element.innerHTML = `<div class="toast-icon">${icon(TOAST_ICONS[kind] || 'info')}</div>
    <div class="toast-copy">
      <div class="toast-title">${esc(toast.title)}</div>
      ${toast.message ? `<div class="toast-message">${esc(toast.message)}</div>` : ''}
    </div>
    <button class="toast-close" type="button" data-action="dismiss-toast" aria-label="关闭通知">${icon('x')}</button>`;
  els.toastRoot.appendChild(element);

  window.setTimeout(() => dismissToast(element), 5600);
}

function dismissToast(element) {
  if (!element || !element.isConnected || element.classList.contains('is-leaving')) return;
  element.classList.add('is-leaving');
  window.setTimeout(() => element.remove(), 240);
}
