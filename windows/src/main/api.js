'use strict';

const {
  parseInstance,
  parseBill,
  parseMachineStock,
  jsonString,
  jsonInt,
  jsonNumber,
  chinaDayStart,
  addDays,
  chinaParts,
} = require('./models');

const BASE_URL = 'https://www.autodl.com/api/v1';
const SUCCESS_CODES = new Set(['Success', 'success', '0']);

class AutoDLError extends Error {
  constructor(kind, message, extra = {}) {
    super(message);
    this.name = 'AutoDLError';
    this.kind = kind;
    this.status = extra.status;
    this.code = extra.code;
  }

  get isAuthFailure() {
    if (this.kind === 'unauthorized') return true;
    if (this.kind === 'api') {
      const code = String(this.code || '');
      const message = String(this.message || '');
      return (
        code === 'AuthorizeFailed' ||
        code === 'Unauthorized' ||
        message.includes('登录超时') ||
        message.includes('重新登录')
      );
    }
    return false;
  }
}

function userMessage(error) {
  if (error instanceof AutoDLError) {
    switch (error.kind) {
      case 'unauthorized':
        return '登录状态已失效，请重新登录 AutoDL';
      case 'http':
        return `AutoDL 服务返回 HTTP ${error.status}`;
      case 'invalidResponse':
        return '无法解析 AutoDL 返回的数据';
      case 'network':
        return `网络请求失败：${error.message}`;
      case 'api':
        return error.message || 'AutoDL 接口请求失败';
      default:
        return error.message || 'AutoDL 请求失败';
    }
  }
  return error && error.message ? error.message : 'AutoDL 请求失败';
}

class AutoDLAPI {
  constructor(token) {
    this.token = token;
  }

  async request(method, path, body) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 20000);
    let response;
    try {
      response = await fetch(`${BASE_URL}${path}`, {
        method,
        headers: {
          Authorization: this.token,
          Accept: 'application/json, text/plain, */*',
          'User-Agent': 'HuNaoAutoDL/1.2.0 (Windows)',
          ...(body ? { 'Content-Type': 'application/json;charset=UTF-8' } : {}),
        },
        body: body ? JSON.stringify(body) : undefined,
        signal: controller.signal,
      });
    } catch (error) {
      if (error && error.name === 'AbortError') {
        throw new AutoDLError('network', '请求超时，请检查网络或代理');
      }
      throw new AutoDLError('network', error && error.message ? error.message : '无法连接 AutoDL');
    } finally {
      clearTimeout(timer);
    }

    if (response.status === 401 || response.status === 403) {
      throw new AutoDLError('unauthorized', '登录已失效');
    }
    if (!response.ok) {
      throw new AutoDLError('http', `HTTP ${response.status}`, { status: response.status });
    }

    let json;
    try {
      json = await response.json();
    } catch {
      throw new AutoDLError('invalidResponse', '响应不是有效 JSON');
    }

    const code = jsonString(json.code) || '';
    const message = jsonString(json.msg) || jsonString(json.message) || '';
    if (!SUCCESS_CODES.has(code)) {
      throw new AutoDLError('api', message, { code });
    }
    return json;
  }

  async fetchInstances() {
    const json = await this.request('POST', '/instance', {
      date_from: '',
      date_to: '',
      page_index: 1,
      page_size: 100,
      status: [],
      charge_type: [],
    });

    const data = json.data;
    let list = null;
    if (data && typeof data === 'object' && !Array.isArray(data) && Array.isArray(data.list)) {
      list = data.list;
    } else if (Array.isArray(data)) {
      list = data;
    }
    if (!list) throw new AutoDLError('invalidResponse', '实例列表格式不正确');
    return list.map(parseInstance).filter(Boolean);
  }

  async fetchGPUStock(instance) {
    if (!instance.machineID) {
      return {
        idleGPUs: 0,
        totalGPUs: null,
        machineID: '',
        gpuName: instance.gpuName,
        requiredGPUs: instance.gpuCount,
        checkedAt: new Date(),
        machineFound: false,
      };
    }

    const body = {
      default_order: true,
      gpu_idle_num: Math.max(instance.gpuCount, 1),
      page_index: 1,
      page_size: 100,
    };
    if (instance.gpuName) body.gpu_type_name = [instance.gpuName];
    if (instance.regionSign) body.region_sign_list = [instance.regionSign];
    if (instance.chargeType) body.charge_type = instance.chargeType;

    const json = await this.request('POST', '/user/machine/list', body);
    const result = parseMachineStock(json, instance.machineID);
    return {
      idleGPUs: result.idleGPUs,
      totalGPUs: result.totalGPUs,
      machineID: instance.machineID,
      gpuName: instance.gpuName,
      requiredGPUs: instance.gpuCount,
      checkedAt: new Date(),
      machineFound: result.machineFound,
    };
  }

  async powerOn(instanceUUID) {
    await this.request('POST', '/instance/power_on', {
      instance_uuid: instanceUUID,
      payload: 'gpu',
    });
  }

  async powerOff(instanceUUID) {
    await this.request('POST', '/instance/power_off', {
      instance_uuid: instanceUUID,
    });
  }

  async fetchBalance() {
    const json = await this.request('GET', '/wallet');
    const data = json.data;
    if (!data || typeof data !== 'object') {
      throw new AutoDLError('invalidResponse', '钱包数据格式不正确');
    }
    const cash = (jsonNumber(data.assets) ?? jsonNumber(data.balance) ?? 0) / 1000;
    const blocked = (jsonNumber(data.blocked_asset) ?? jsonNumber(data.blocked_assets) ?? 0) / 1000;
    const voucher = (jsonNumber(data.voucher_balance) ?? jsonNumber(data.voucher) ?? 0) / 1000;
    return {
      cash,
      blocked,
      voucher,
      paymentMethod: jsonString(data.payment_method),
      fetchedAt: new Date(),
    };
  }

  async fetchBills(from, to) {
    const dateFrom = formatDateArg(from);
    const dateTo = formatDateArg(to);
    const records = [];
    const seen = new Set();
    let page = 1;

    while (page <= 6) {
      const json = await this.request('POST', '/bill/list', {
        order_uuid: '',
        sub_name: '',
        date_from: dateFrom,
        date_to: dateTo,
        page_index: page,
        page_size: 500,
        bill_type: '',
      });
      const data = json.data;
      if (!data || typeof data !== 'object' || !Array.isArray(data.list)) {
        throw new AutoDLError('invalidResponse', '账单数据格式不正确');
      }
      for (const item of data.list) {
        const record = parseBill(item);
        if (record && !seen.has(record.id)) {
          seen.add(record.id);
          records.push(record);
        }
      }
      const total = jsonInt(data.result_total) ?? records.length;
      if (data.list.length === 0 || records.length >= total) break;
      page += 1;
    }
    return records;
  }
}

function formatDateArg(date) {
  const parts = chinaParts(date);
  return `${parts.year}-${String(parts.month).padStart(2, '0')}-${String(parts.day).padStart(2, '0')}`;
}

function defaultBillingRange() {
  const end = new Date();
  const start = addDays(chinaDayStart(end), -35);
  return { start, end };
}

module.exports = {
  AutoDLAPI,
  AutoDLError,
  userMessage,
  defaultBillingRange,
};
