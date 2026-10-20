'use strict';

const GIB = 1024 * 1024 * 1024;
const DAY_MS = 24 * 60 * 60 * 1000;
const CHINA_OFFSET_MS = 8 * 60 * 60 * 1000;

const CHARGE_LABELS = {
  payg: '按量计费',
  daily: '包日',
  weekly: '包周',
  monthly: '包月',
};

const STATE_INFO = {
  running: { label: '运行中', tint: 'mint', symbol: 'play' },
  stopped: { label: '已关机', tint: 'muted', symbol: 'stop' },
  starting: { label: '启动中', tint: 'amber', symbol: 'loader' },
  stopping: { label: '关机中', tint: 'rose', symbol: 'loader' },
  unknown: { label: '未知状态', tint: 'violet', symbol: 'help' },
};

const BILL_INFO = {
  charge: { symbol: 'bolt', tint: 'aqua', outflow: true },
  refund: { symbol: 'undo', tint: 'mint', outflow: false },
  recharge: { symbol: 'plus', tint: 'mint', outflow: false },
  withdraw: { symbol: 'arrow-up-right', tint: 'amber', outflow: true },
};

function jsonString(value) {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed || null;
  }
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  return null;
}

function jsonNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const cleaned = value.replace(/,/g, '').trim();
    if (!cleaned) return null;
    const parsed = Number(cleaned);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function jsonInt(value) {
  const number = jsonNumber(value);
  return number == null ? null : Math.trunc(number);
}

function jsonInt64(value) {
  return jsonInt(value);
}

function jsonBool(value) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (value === 'true') return true;
  if (value === 'false') return false;
  return null;
}

function parseDate(value) {
  if (value && typeof value === 'object' && !(value instanceof Date)) {
    if (jsonBool(value.Valid) === false) return null;
    return parseDate(value.Time);
  }
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value === 'number' && Number.isFinite(value)) {
    const ms = value > 1e11 ? value : value * 1000;
    const date = new Date(ms);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (typeof value !== 'string') return null;
  const text = value.trim();
  if (!text) return null;

  const plain = text.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$/);
  if (plain) {
    const date = new Date(
      `${plain[1]}-${plain[2]}-${plain[3]}T${plain[4]}:${plain[5]}:${plain[6] || '00'}+08:00`
    );
    return Number.isNaN(date.getTime()) ? null : date;
  }
  const dayOnly = text.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (dayOnly) {
    const date = new Date(`${dayOnly[1]}-${dayOnly[2]}-${dayOnly[3]}T00:00:00+08:00`);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  const date = new Date(text);
  return Number.isNaN(date.getTime()) ? null : date;
}

function instanceState(rawStatus) {
  const status = String(rawStatus || '').toLowerCase();
  if (status === 'running') return 'running';
  if (['shutdown', 'stopped', 'poweroff', 'power_off'].includes(status)) return 'stopped';
  if (['starting', 'powering_on', 'creating', 'restarting', 'restart'].includes(status)) return 'starting';
  if (['shutting_down', 'stopping'].includes(status)) return 'stopping';
  return 'unknown';
}

function parseInstance(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const id =
    jsonString(raw.uuid) || jsonString(raw.instance_uuid) || jsonString(raw.id);
  if (!id) return null;

  const usage = raw.usage_info && typeof raw.usage_info === 'object' ? raw.usage_info : {};
  const name = jsonString(raw.name) || jsonString(raw.instance_name) || '未命名实例';
  const gpuName =
    jsonString(raw.gpu_type_name) ||
    jsonString(raw.snapshot_gpu_type_name) ||
    jsonString(raw.snapshot_gpu_alias_name) ||
    jsonString(raw.gpu_name) ||
    jsonString(raw.gpu_type) ||
    'GPU';
  const gpuCount = Math.max(
    jsonInt(raw.req_gpu_amount) ?? jsonInt(raw.gpu_num) ?? jsonInt(raw.gpu_amount) ?? 1,
    1
  );

  const expandDataDisk = jsonInt64(raw.expand_data_disk_size);
  const dataDiskTotal =
    jsonInt64(usage.data_disk_total_size) ??
    (expandDataDisk == null ? null : 50 * GIB + expandDataDisk);

  const releaseDates = [parseDate(raw.rent_deadline), parseDate(raw.expired_at)].filter(Boolean);
  const releaseAt = releaseDates.length
    ? new Date(Math.min(...releaseDates.map((date) => date.getTime())))
    : null;

  return {
    id,
    name,
    rawStatus: jsonString(raw.status) || jsonString(raw.instance_status) || 'unknown',
    regionName: jsonString(raw.region_name) || jsonString(raw.region_alias) || '',
    regionSign: jsonString(raw.region_sign) || jsonString(raw.region) || '',
    gpuName,
    gpuCount,
    machineID: jsonString(raw.machine_id) || jsonString(raw.machine_alias) || '',
    chargeType: jsonString(raw.charge_type) || '',
    startedAt: parseDate(raw.started_at),
    statusAt: parseDate(raw.status_at) || parseDate(raw.updated_at),
    sshCommand: jsonString(raw.ssh_command),
    rootPassword: jsonString(raw.root_password),
    jupyterDomain: jsonString(raw.jupyter_domain),
    systemDiskTotal: jsonInt64(raw.root_fs_total_size) ?? jsonInt64(usage.root_fs_total_size),
    systemDiskUsed: jsonInt64(raw.root_fs_used_size) ?? jsonInt64(usage.root_fs_used_size),
    dataDiskTotal,
    dataDiskUsed: jsonInt64(usage.data_disk_used_size),
    diskExpandAvailable: jsonInt64(raw.disk_expand_available),
    memoryTotal:
      jsonInt64(usage.mem_limit) ?? jsonInt64(raw.mem_limit) ?? jsonInt64(raw.mem_limit_in_byte),
    memoryUsed: jsonInt64(usage.mem_usage) ?? jsonInt64(raw.mem_usage),
    releaseAt,
  };
}

function parseBill(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const id = jsonString(raw.uuid) || (jsonInt(raw.id) != null ? String(jsonInt(raw.id)) : null);
  if (!id) return null;
  const details = raw.details && typeof raw.details === 'object' ? raw.details : {};
  const discount = raw.discount_detail && typeof raw.discount_detail === 'object' ? raw.discount_detail : {};
  const createdAt = parseDate(raw.created_at) || parseDate(raw.confirm_at) || new Date();
  return {
    id,
    createdAt,
    type: (jsonString(raw.bill_type) || 'charge').toLowerCase(),
    amount: Math.max(0, (jsonNumber(raw.asset) || 0) / 1000),
    payByBalance: (jsonNumber(raw.pay_by_balance) || 0) / 1000,
    payByVoucher: (jsonNumber(raw.pay_by_voucher) || 0) / 1000,
    balanceAfter: jsonNumber(raw.balance) == null ? null : jsonNumber(raw.balance) / 1000,
    gpuType: jsonString(details.gpu_type),
    regionName: jsonString(details.region_name) || jsonString(details.region_sign),
    machineID: jsonString(details.machine_id),
    chargeDuration: jsonInt(details.charge_duration),
    chargeFrom: parseDate(details.charge_from),
    originPrice: jsonNumber(discount.origin_price) == null ? null : jsonNumber(discount.origin_price) / 1000,
    discountAmount: (jsonNumber(discount.discount_sum) || 0) / 1000,
  };
}

function parseMachineStock(json, targetMachineID) {
  let machines = [];
  const data = json && json.data;
  if (data && typeof data === 'object' && !Array.isArray(data)) {
    if (Array.isArray(data.list)) machines = data.list;
    else if (Array.isArray(data.machines)) machines = data.machines;
    else machines = [data];
  } else if (Array.isArray(data)) {
    machines = data;
  }

  const normalizedTarget = String(targetMachineID || '').trim().toLowerCase();
  const target = machines.find((machine) => {
    if (!machine || typeof machine !== 'object') return false;
    const raw = jsonString(machine.machine_id) || jsonString(machine.machine_uuid) || jsonString(machine.id) || '';
    return raw.trim().toLowerCase() === normalizedTarget;
  });

  if (!target || !normalizedTarget) {
    return { idleGPUs: 0, totalGPUs: null, machineFound: false };
  }

  const idle =
    jsonInt(target.gpu_idle_num) ?? jsonInt(target.idle_gpu_num) ?? jsonInt(target.gpu_idle_count) ?? 0;
  const explicitTotal =
    jsonInt(target.gpu_all_num) ?? jsonInt(target.gpu_total_num) ?? jsonInt(target.total_gpu_num);
  const possibleTotal = jsonInt(target.gpu_num);
  const total = explicitTotal ?? (possibleTotal == null ? null : Math.max(possibleTotal, idle));

  return { idleGPUs: Math.max(0, idle), totalGPUs: total, machineFound: true };
}

function chinaParts(date) {
  const formatted = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date);
  const parts = {};
  for (const part of formatted) {
    if (part.type !== 'literal') parts[part.type] = part.value;
  }
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: Number(parts.hour),
    minute: Number(parts.minute),
    second: Number(parts.second),
  };
}

function chinaDayStart(date) {
  const shifted = new Date(date.getTime() + CHINA_OFFSET_MS);
  shifted.setUTCHours(0, 0, 0, 0);
  return new Date(shifted.getTime() - CHINA_OFFSET_MS);
}

function chinaDayKey(date) {
  const parts = chinaParts(date);
  return `${parts.year}-${String(parts.month).padStart(2, '0')}-${String(parts.day).padStart(2, '0')}`;
}

function chinaMonthStart(date) {
  const parts = chinaParts(date);
  return new Date(`${parts.year}-${String(parts.month).padStart(2, '0')}-01T00:00:00+08:00`);
}

function addDays(date, days) {
  return new Date(date.getTime() + days * DAY_MS);
}

function formatTime(date) {
  if (!date) return '尚未同步';
  const parts = chinaParts(date);
  return `${String(parts.hour).padStart(2, '0')}:${String(parts.minute).padStart(2, '0')}:${String(parts.second).padStart(2, '0')}`;
}

function formatRelative(value) {
  const date = value instanceof Date ? value : parseDate(value);
  if (!date) return '尚未同步';
  const seconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000));
  if (seconds < 5) return '刚刚';
  if (seconds < 60) return `${seconds} 秒前`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} 分钟前`;
  return formatTime(date);
}

function formatBillDay(date) {
  const parts = chinaParts(date);
  return `${parts.month}月${parts.day}日`;
}

function formatBillDayTime(date) {
  const parts = chinaParts(date);
  return `${parts.month}月${parts.day}日 ${String(parts.hour).padStart(2, '0')}:${String(parts.minute).padStart(2, '0')}`;
}

function formatChartDay(date) {
  const parts = chinaParts(date);
  return `${parts.month}/${parts.day}`;
}

function formatReleaseDate(date) {
  const parts = chinaParts(date);
  return `${parts.year}-${String(parts.month).padStart(2, '0')}-${String(parts.day).padStart(2, '0')}`;
}

function formatReleaseShort(date) {
  const parts = chinaParts(date);
  return `${String(parts.year).slice(-2)}-${String(parts.month).padStart(2, '0')}-${String(parts.day).padStart(2, '0')} ${String(parts.hour).padStart(2, '0')}:${String(parts.minute).padStart(2, '0')}`;
}

function formatFullDate(date) {
  const parts = chinaParts(date);
  const weekday = new Intl.DateTimeFormat('zh-CN', {
    timeZone: 'Asia/Shanghai',
    weekday: 'long',
  }).format(date);
  return `${parts.year}年${parts.month}月${parts.day}日 ${weekday}`;
}

function formatStorage(bytes) {
  const gib = Math.max(0, Number(bytes) || 0) / GIB;
  if (gib >= 1024) return `${(gib / 1024).toFixed(2)} TB`;
  if (gib >= 100) return `${gib.toFixed(0)} GB`;
  return `${gib.toFixed(1)} GB`;
}

const currencyFormatter = new Intl.NumberFormat('zh-CN', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

function formatCurrency(value) {
  return `¥${currencyFormatter.format(Number(value) || 0)}`;
}

function instanceView(instance) {
  if (!instance) return null;
  const state = instanceState(instance.rawStatus);
  const info = STATE_INFO[state];
  const chargeLabel =
    CHARGE_LABELS[String(instance.chargeType || '').toLowerCase()] ||
    (instance.chargeType ? instance.chargeType : '未知计费');

  const systemFree =
    instance.systemDiskTotal == null || instance.systemDiskUsed == null
      ? null
      : Math.max(0, instance.systemDiskTotal - instance.systemDiskUsed);
  const dataFree =
    instance.dataDiskTotal == null || instance.dataDiskUsed == null
      ? null
      : Math.max(0, instance.dataDiskTotal - instance.dataDiskUsed);
  const freeParts = [systemFree, dataFree].filter((value) => value != null);
  const totalParts = [instance.systemDiskTotal, instance.dataDiskTotal].filter((value) => value != null);
  const storageFree = freeParts.length ? freeParts.reduce((sum, value) => sum + value, 0) : null;
  const storageTotal = totalParts.length ? totalParts.reduce((sum, value) => sum + value, 0) : null;

  const freeStorageText = storageFree == null ? '待同步' : formatStorage(storageFree);
  const storageDetails = [];
  if (systemFree != null) storageDetails.push(`系统 ${formatStorage(systemFree)}`);
  if (dataFree != null) storageDetails.push(`数据 ${formatStorage(dataFree)}`);

  const memoryFree =
    instance.memoryTotal == null || instance.memoryUsed == null
      ? null
      : Math.max(0, instance.memoryTotal - instance.memoryUsed);
  const memoryDetail =
    instance.memoryTotal == null
      ? '内存用量待同步'
      : `已用 ${formatStorage(instance.memoryUsed || 0)} / 共 ${formatStorage(instance.memoryTotal)}`;

  let releaseShort = '待同步';
  let releaseCountdown = null;
  let releaseDetail = 'AutoDL 暂未返回释放时间';
  if (instance.releaseAt) {
    releaseShort = formatReleaseShort(instance.releaseAt);
    const days = Math.round(
      (chinaDayStart(instance.releaseAt).getTime() - chinaDayStart(new Date()).getTime()) / DAY_MS
    );
    releaseCountdown = days < 0 ? '已到期' : days === 0 ? '今天' : `${days} 天后`;
    releaseDetail = `AutoDL 预计释放时间 ${formatReleaseDate(instance.releaseAt)} · ${releaseCountdown}`;
  }

  return {
    id: instance.id,
    name: instance.name,
    rawStatus: instance.rawStatus,
    state,
    stateLabel: info.label,
    stateTint: info.tint,
    stateSymbol: info.symbol,
    displayRegion: instance.regionName || instance.regionSign || '未知地区',
    regionName: instance.regionName,
    gpuName: instance.gpuName,
    gpuCount: instance.gpuCount,
    machineID: instance.machineID,
    machineLabel: instance.machineID || '主机待同步',
    chargeType: instance.chargeType,
    chargeLabel,
    startedAt: instance.startedAt ? instance.startedAt.toISOString() : null,
    startedLabel:
      instance.startedAt && state === 'running' ? formatBillDayTime(instance.startedAt) : null,
    statusLabel: instance.statusAt ? formatRelative(instance.statusAt) : null,
    sshCommand: instance.sshCommand,
    jupyterDomain: instance.jupyterDomain,
    shortID: instance.id.length > 8 ? instance.id.slice(-8) : instance.id,
    systemDiskTotal: instance.systemDiskTotal,
    systemDiskUsed: instance.systemDiskUsed,
    dataDiskTotal: instance.dataDiskTotal,
    dataDiskUsed: instance.dataDiskUsed,
    storageFreeBytes: storageFree,
    storageTotalBytes: storageTotal,
    storageFreeLabel: freeStorageText,
    storageDetailLabel: storageDetails.length ? storageDetails.join(' · ') : '存储用量待同步',
    storageUsedFraction:
      storageTotal && storageFree != null ? (storageTotal - storageFree) / storageTotal : null,
    memoryFreeBytes: memoryFree,
    memoryUsedBytes: instance.memoryUsed,
    memoryTotalBytes: instance.memoryTotal,
    memoryFreeLabel: memoryFree == null ? '待同步' : formatStorage(memoryFree),
    memoryDetailLabel: memoryDetail,
    memoryUsedFraction:
      instance.memoryTotal && instance.memoryUsed != null
        ? Math.min(Math.max(instance.memoryUsed / instance.memoryTotal, 0), 1)
        : null,
    releaseAt: instance.releaseAt ? instance.releaseAt.toISOString() : null,
    releaseLabel: releaseShort,
    releaseCountdown,
    releaseDetail,
  };
}

class BillingSnapshot {
  constructor(records, fetchedAt) {
    this.records = Array.isArray(records) ? records : [];
    this.fetchedAt = fetchedAt || new Date();
  }

  chargeRecords() {
    return this.records.filter((record) => billType(record.type) === 'charge');
  }

  netSpendOn(day) {
    const key = chinaDayKey(day);
    const net = this.records.reduce((sum, record) => {
      if (chinaDayKey(record.chargeFrom || record.createdAt) !== key) return sum;
      const type = billType(record.type);
      if (type === 'charge') return sum + record.amount;
      if (type === 'refund') return sum - record.amount;
      return sum;
    }, 0);
    return Math.max(0, net);
  }

  netSpendSince(start) {
    const net = this.records.reduce((sum, record) => {
      if ((record.chargeFrom || record.createdAt) < start) return sum;
      const type = billType(record.type);
      if (type === 'charge') return sum + record.amount;
      if (type === 'refund') return sum - record.amount;
      return sum;
    }, 0);
    return Math.max(0, net);
  }

  dailySeries(days) {
    const end = chinaDayStart(new Date());
    const series = [];
    for (let offset = days - 1; offset >= 0; offset -= 1) {
      const date = addDays(end, -offset);
      series.push({
        date,
        key: chinaDayKey(date),
        label: formatChartDay(date),
        amount: this.netSpendOn(date),
        isToday: offset === 0,
      });
    }
    return series;
  }

  totalSpend(days) {
    return this.dailySeries(days).reduce((sum, day) => sum + day.amount, 0);
  }

  todaySpend() {
    return this.totalSpend(1);
  }

  last7Spend() {
    return this.totalSpend(7);
  }

  monthSpend() {
    return this.netSpendSince(chinaMonthStart(new Date()));
  }

  averageDailySpend() {
    return this.last7Spend() / 7;
  }

  estimatedDaysRemaining(balance) {
    const average = this.averageDailySpend();
    if (balance == null || balance <= 0 || average <= 0.01) return null;
    return Math.max(0, Math.trunc(balance / average));
  }

  gpuConsumption(days = 30) {
    const today = chinaDayStart(new Date());
    const start = addDays(today, -(days - 1));
    const totals = new Map();
    for (const record of this.chargeRecords()) {
      const effective = record.chargeFrom || record.createdAt;
      if (effective < start) continue;
      const key = record.gpuType && record.gpuType.trim() ? record.gpuType : '其他消费';
      totals.set(key, (totals.get(key) || 0) + record.amount);
    }
    return [...totals.entries()]
      .map(([label, amount]) => ({ label, amount }))
      .sort((a, b) => b.amount - a.amount);
  }

  recentRecords() {
    return [...this.records].sort((a, b) => b.createdAt - a.createdAt).slice(0, 12);
  }
}

function billType(type) {
  return BILL_INFO[String(type || '').toLowerCase()] ? String(type).toLowerCase() : 'charge';
}

function durationLabel(seconds) {
  if (!seconds || seconds <= 0) return null;
  if (seconds >= 3600) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    return minutes === 0 ? `${hours} 小时` : `${hours} 小时 ${minutes} 分`;
  }
  if (seconds >= 60) return `${Math.floor(seconds / 60)} 分钟`;
  return `${seconds} 秒`;
}

function billTitle(record) {
  const type = billType(record.type);
  if (type === 'charge') {
    if (record.gpuType) {
      return record.regionName ? `${record.gpuType} · ${record.regionName}` : record.gpuType;
    }
    return 'GPU 消费';
  }
  if (type === 'refund') return '账单退款';
  if (type === 'recharge') return '账户充值';
  return '账户提现';
}

function billView(record) {
  const type = billType(record.type);
  const info = BILL_INFO[type];
  const duration = durationLabel(record.chargeDuration);
  const time = formatBillDayTime(record.chargeFrom || record.createdAt);
  const details = [];
  if (record.payByBalance > 0) details.push(`余额支付 ${formatCurrency(record.payByBalance)}`);
  if (record.payByVoucher > 0) details.push(`代金券 ${formatCurrency(record.payByVoucher)}`);
  if (record.originPrice != null && record.discountAmount > 0) {
    details.push(`原价 ${formatCurrency(record.originPrice)} · 优惠 ${formatCurrency(record.discountAmount)}`);
  }
  if (record.balanceAfter != null) details.push(`支付后余额 ${formatCurrency(record.balanceAfter)}`);
  if (record.machineID) details.push(`主机 ${record.machineID}`);

  return {
    id: record.id,
    type,
    symbol: info.symbol,
    tint: info.tint,
    isOutflow: info.outflow,
    title: billTitle(record),
    subtitle: duration ? `${time} · ${duration}` : time,
    timeLabel: time,
    amountLabel: formatCurrency(record.amount),
    signedAmountLabel: `${info.outflow ? '-' : '+'}${formatCurrency(record.amount)}`,
    discountAmount: record.discountAmount,
    discountLabel:
      record.discountAmount > 0 ? `省 ${formatCurrency(record.discountAmount)}` : null,
    detailHelp: details.join(' · '),
    effectiveAt: (record.chargeFrom || record.createdAt).toISOString(),
    createdAt: record.createdAt.toISOString(),
  };
}

function balanceView(balance) {
  if (!balance) return null;
  const available = Math.max(0, balance.cash) + Math.max(0, balance.voucher);
  return {
    cash: balance.cash,
    blocked: balance.blocked,
    voucher: balance.voucher,
    available,
    formattedAvailable: formatCurrency(available),
    formattedCash: formatCurrency(balance.cash),
    formattedVoucher: formatCurrency(balance.voucher),
    formattedBlocked: formatCurrency(balance.blocked),
    fetchedAt: balance.fetchedAt ? balance.fetchedAt.toISOString() : null,
  };
}

function stockView(stock) {
  if (!stock) return null;
  const total = stock.totalGPUs;
  return {
    idleGPUs: stock.idleGPUs,
    totalGPUs: total,
    machineID: stock.machineID,
    gpuName: stock.gpuName,
    requiredGPUs: stock.requiredGPUs,
    machineFound: stock.machineFound,
    checkedAt: stock.checkedAt ? stock.checkedAt.toISOString() : null,
    isAvailable:
      stock.machineFound && stock.idleGPUs > 0 && stock.idleGPUs >= Math.max(stock.requiredGPUs, 1),
    occupiedGPUs: total == null ? null : Math.max(0, total - stock.idleGPUs),
  };
}

function billingView(snapshot, balanceAvailable) {
  if (!snapshot) return null;
  const series30 = snapshot.dailySeries(30).map(({ date, ...rest }) => ({
    ...rest,
    date: date.toISOString(),
  }));
  const slices = snapshot.gpuConsumption(30);
  const sliceTotal = slices.reduce((sum, slice) => sum + slice.amount, 0);
  const dailyAverage = snapshot.averageDailySpend();
  return {
    fetchedAt: snapshot.fetchedAt.toISOString(),
    fetchedLabel: formatRelative(snapshot.fetchedAt),
    recordCount: snapshot.records.length,
    chargeCount: snapshot.chargeRecords().length,
    series30,
    gpuSlices: slices.map((slice) => ({
      ...slice,
      percent: sliceTotal > 0 ? Math.round((slice.amount / sliceTotal) * 100) : 0,
    })),
    summary: {
      total14: snapshot.totalSpend(14),
      total30: snapshot.totalSpend(30),
      today: snapshot.todaySpend(),
      last7: snapshot.last7Spend(),
      month: snapshot.monthSpend(),
      average: dailyAverage,
      daysRemaining: snapshot.estimatedDaysRemaining(balanceAvailable),
    },
    recent: snapshot.recentRecords().map(billView),
  };
}

module.exports = {
  GIB,
  DAY_MS,
  STATE_INFO,
  BILL_INFO,
  jsonString,
  jsonNumber,
  jsonInt,
  jsonInt64,
  jsonBool,
  parseDate,
  instanceState,
  parseInstance,
  parseBill,
  parseMachineStock,
  chinaParts,
  chinaDayStart,
  chinaDayKey,
  chinaMonthStart,
  addDays,
  formatTime,
  formatRelative,
  formatBillDay,
  formatBillDayTime,
  formatChartDay,
  formatReleaseDate,
  formatReleaseShort,
  formatFullDate,
  formatStorage,
  formatCurrency,
  instanceView,
  BillingSnapshot,
  billType,
  durationLabel,
  billView,
  balanceView,
  stockView,
  billingView,
};
