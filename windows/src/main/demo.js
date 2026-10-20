'use strict';

const { GIB, chinaDayStart, addDays } = require('./models');

const RELEASE_DAYS = [3, 12, 20];
const WEEKDAY_BASE = [4.6, 8.2, 9.6, 8.8, 7.1, 11.4, 10.2];

function seed() {
  const now = new Date();
  const today = chinaDayStart(now);

  const instances = [
    {
      id: 'demo-8f3c1a92',
      name: 'rtx4090-lab',
      rawStatus: 'shutdown',
      regionName: '北京B区',
      regionSign: 'beijing-b',
      gpuName: 'RTX 4090',
      gpuCount: 1,
      machineID: 'seetacloud-4090-07',
      chargeType: 'payg',
      startedAt: null,
      statusAt: new Date(now.getTime() - 18 * 60 * 1000),
      sshCommand: null,
      rootPassword: null,
      jupyterDomain: null,
      systemDiskTotal: 30 * GIB,
      systemDiskUsed: 11 * GIB,
      dataDiskTotal: 50 * GIB,
      dataDiskUsed: 19 * GIB,
      diskExpandAvailable: 0,
      memoryTotal: 64 * GIB,
      memoryUsed: 7 * GIB,
      releaseAt: addDays(now, RELEASE_DAYS[0]),
    },
    {
      id: 'demo-2b7d4c10',
      name: 'a100-train',
      rawStatus: 'running',
      regionName: '内蒙A区',
      regionSign: 'neimeng-a',
      gpuName: 'A100-SXM4-80GB',
      gpuCount: 1,
      machineID: 'seetacloud-a100-03',
      chargeType: 'payg',
      startedAt: new Date(now.getTime() - 3 * 60 * 60 * 1000),
      statusAt: new Date(now.getTime() - 60 * 1000),
      sshCommand: 'ssh -p 22333 root@connect.example.com',
      rootPassword: null,
      jupyterDomain: 'https://jupyter.example.com',
      systemDiskTotal: 30 * GIB,
      systemDiskUsed: 18 * GIB,
      dataDiskTotal: 50 * GIB,
      dataDiskUsed: 36 * GIB,
      diskExpandAvailable: 0,
      memoryTotal: 120 * GIB,
      memoryUsed: 74 * GIB,
      releaseAt: addDays(now, RELEASE_DAYS[1]),
    },
    {
      id: 'demo-5c9e3f61',
      name: '3090-infer',
      rawStatus: 'shutdown',
      regionName: '上海A区',
      regionSign: 'shanghai-a',
      gpuName: 'RTX 3090',
      gpuCount: 1,
      machineID: 'seetacloud-3090-02',
      chargeType: 'payg',
      startedAt: null,
      statusAt: new Date(now.getTime() - 5 * 60 * 60 * 1000),
      sshCommand: null,
      rootPassword: null,
      jupyterDomain: null,
      systemDiskTotal: 30 * GIB,
      systemDiskUsed: 9 * GIB,
      dataDiskTotal: 50 * GIB,
      dataDiskUsed: 23 * GIB,
      diskExpandAvailable: 0,
      memoryTotal: 32 * GIB,
      memoryUsed: 4 * GIB,
      releaseAt: addDays(now, RELEASE_DAYS[2]),
    },
  ];

  const stock = {
    idleGPUs: 2,
    totalGPUs: 8,
    machineID: 'seetacloud-4090-07',
    gpuName: 'RTX 4090',
    requiredGPUs: 1,
    checkedAt: now,
    machineFound: true,
  };

  const balance = {
    cash: 186.4,
    blocked: 12.5,
    voucher: 30.0,
    paymentMethod: 'balance',
    fetchedAt: now,
  };

  return {
    instances,
    selectedInstanceId: instances[0].id,
    stock,
    balance,
    billing: { records: billRecords(today, now), fetchedAt: now },
    activity: [
      demoEvent('success', '自动开机成功', 'RTX 4090 出现空闲，已为 rtx4090-lab 开机', 45),
      demoEvent('info', '发现空闲显卡', '北京B区 · 2 张 RTX 4090 可用', 150),
      demoEvent('success', '已自动连接 AutoDL', '正在守护 3 个实例', 320),
      demoEvent('warning', '余额提醒阈值', '可用余额低于 ¥20.00 时将提醒', 640),
      demoEvent('info', '账单已同步', '近 30 天消费构成已更新', 980),
    ],
  };
}

function demoEvent(kind, title, detail, secondsAgo) {
  return {
    id: `demo-activity-${title}-${secondsAgo}`,
    date: new Date(Date.now() - secondsAgo * 1000),
    kind,
    title,
    detail,
  };
}

function billRecords(today, now) {
  const records = [];
  for (let offset = 34; offset >= 0; offset -= 1) {
    const day = addDays(today, -offset);
    const weekday = new Date(day.getTime() + 8 * 60 * 60 * 1000).getUTCDay();
    const base = WEEKDAY_BASE[weekday];
    const count = offset === 0 ? 1 : 3;

    for (let index = 0; index < count; index += 1) {
      const timestamp =
        offset === 0
          ? new Date(now.getTime() - 5 * 60 * 1000)
          : new Date(day.getTime() + (10 + index * 4) * 60 * 60 * 1000);
      const amount = (base / count) * (0.86 + ((offset + index) % 4) * 0.07);
      const origin = amount * 1.18;
      records.push({
        id: `demo-bill-${offset}-${index}`,
        createdAt: timestamp,
        type: 'charge',
        amount,
        payByBalance: amount * 0.82,
        payByVoucher: amount * 0.18,
        balanceAfter: Math.max(0, 216.4 - (34 - offset) * 7.4),
        gpuType: index === 2 ? 'RTX 3090' : 'RTX 4090',
        regionName: index === 2 ? '内蒙A区' : '北京B区',
        machineID: index === 2 ? 'seetacloud-3090-02' : 'seetacloud-4090-07',
        chargeDuration: 3600,
        chargeFrom: timestamp,
        originPrice: origin,
        discountAmount: origin - amount,
      });
    }
  }

  const rechargeDate = addDays(today, -9);
  const refundDate = addDays(today, -2);
  records.push({
    id: 'demo-recharge',
    createdAt: rechargeDate,
    type: 'recharge',
    amount: 100,
    payByBalance: 100,
    payByVoucher: 0,
    balanceAfter: 300,
    gpuType: null,
    regionName: null,
    machineID: null,
    chargeDuration: null,
    chargeFrom: null,
    originPrice: null,
    discountAmount: 0,
  });
  records.push({
    id: 'demo-refund',
    createdAt: refundDate,
    type: 'refund',
    amount: 1.8,
    payByBalance: 1.8,
    payByVoucher: 0,
    balanceAfter: 231.8,
    gpuType: 'RTX 4090',
    regionName: '北京B区',
    machineID: 'seetacloud-4090-07',
    chargeDuration: 600,
    chargeFrom: refundDate,
    originPrice: 1.8,
    discountAmount: 0,
  });

  return records;
}

module.exports = { seed };
