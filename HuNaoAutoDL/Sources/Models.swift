import Foundation
import SwiftUI

enum SessionPhase: Equatable {
    case checking
    case loggedOut
    case signedIn
}

enum InstanceState: String {
    case running
    case stopped
    case starting
    case stopping
    case unknown

    var label: String {
        switch self {
        case .running: return "运行中"
        case .stopped: return "已关机"
        case .starting: return "启动中"
        case .stopping: return "关机中"
        case .unknown: return "未知状态"
        }
    }

    var isPoweredOff: Bool { self == .stopped }
    var isBusy: Bool { self == .starting || self == .stopping }
}

struct AutoDLInstance: Identifiable, Equatable {
    let id: String
    let name: String
    let rawStatus: String
    let regionName: String
    let regionSign: String
    let gpuName: String
    let gpuCount: Int
    let machineID: String
    let chargeType: String
    let startedAt: Date?
    let statusAt: Date?
    let sshCommand: String?
    let rootPassword: String?
    let jupyterDomain: String?
    let systemDiskTotal: Int64?
    let systemDiskUsed: Int64?
    let dataDiskTotal: Int64?
    let dataDiskUsed: Int64?
    let diskExpandAvailable: Int64?
    let memoryTotal: Int64?
    let memoryUsed: Int64?
    let releaseAt: Date?

    var state: InstanceState {
        switch rawStatus.lowercased() {
        case "running":
            return .running
        case "shutdown", "stopped", "poweroff", "power_off":
            return .stopped
        case "starting", "powering_on", "creating", "restarting", "restart":
            return .starting
        case "shutting_down", "stopping":
            return .stopping
        default:
            return .unknown
        }
    }

    var chargeLabel: String {
        switch chargeType.lowercased() {
        case "payg": return "按量计费"
        case "daily": return "包日"
        case "weekly": return "包周"
        case "monthly": return "包月"
        case "": return "未知计费"
        default: return chargeType
        }
    }

    var displayRegion: String {
        if !regionName.isEmpty { return regionName }
        if !regionSign.isEmpty { return regionSign }
        return "未知地区"
    }

    var shortID: String {
        guard id.count > 8 else { return id }
        return String(id.suffix(8))
    }

    var systemDiskFree: Int64? {
        guard let total = systemDiskTotal, let used = systemDiskUsed else { return nil }
        return max(0, total - used)
    }

    var dataDiskFree: Int64? {
        guard let total = dataDiskTotal, let used = dataDiskUsed else { return nil }
        return max(0, total - used)
    }

    var storageFreeBytes: Int64? {
        let parts = [systemDiskFree, dataDiskFree].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }

    var storageTotalBytes: Int64? {
        let parts = [systemDiskTotal, dataDiskTotal].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }

    var storageFreeLabel: String {
        guard let storageFreeBytes else { return "待同步" }
        return AppFormat.storage(storageFreeBytes)
    }

    var storageDetailLabel: String {
        var parts: [String] = []
        if let systemDiskFree {
            parts.append("系统 \(AppFormat.storage(systemDiskFree))")
        }
        if let dataDiskFree {
            parts.append("数据 \(AppFormat.storage(dataDiskFree))")
        }
        return parts.isEmpty ? "存储用量待同步" : parts.joined(separator: " · ")
    }

    var storageUsedFraction: Double? {
        guard let total = storageTotalBytes, total > 0,
              let free = storageFreeBytes else { return nil }
        return Double(total - free) / Double(total)
    }

    var memoryFreeBytes: Int64? {
        guard let total = memoryTotal, let used = memoryUsed else { return nil }
        return max(0, total - used)
    }

    var memoryFreeLabel: String {
        guard let memoryFreeBytes else { return "待同步" }
        return AppFormat.storage(memoryFreeBytes)
    }

    var memoryDetailLabel: String {
        guard let total = memoryTotal, total > 0 else { return "内存用量待同步" }
        let used = memoryUsed ?? 0
        return "已用 \(AppFormat.storage(used)) / 共 \(AppFormat.storage(total))"
    }

    var memoryUsedFraction: Double? {
        guard let total = memoryTotal, total > 0, let used = memoryUsed else { return nil }
        return min(max(Double(used) / Double(total), 0), 1)
    }

    var releaseLabel: String {
        guard let releaseAt else { return "待同步" }
        return AppFormat.releaseShort.string(from: releaseAt)
    }

    var releaseCountdownLabel: String? {
        guard let releaseAt else { return nil }
        let calendar = AppTime.calendar
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: releaseAt)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        if days < 0 { return "已到期" }
        if days == 0 { return "今天" }
        return "\(days) 天后"
    }

    var releaseDetailLabel: String {
        guard let releaseAt, let countdown = releaseCountdownLabel else {
            return "AutoDL 暂未返回释放时间"
        }
        return "AutoDL 预计释放时间 \(AppFormat.releaseDate.string(from: releaseAt)) · \(countdown)"
    }

    static func parse(_ raw: [String: Any]) -> AutoDLInstance? {
        guard let uuid = jsonString(raw["uuid"])
            ?? jsonString(raw["instance_uuid"])
            ?? jsonString(raw["id"])
        else { return nil }

        let name = jsonString(raw["name"])
            ?? jsonString(raw["instance_name"])
            ?? "未命名实例"
        let status = jsonString(raw["status"])
            ?? jsonString(raw["instance_status"])
            ?? "unknown"
        let gpuName = jsonString(raw["gpu_type_name"])
            ?? jsonString(raw["snapshot_gpu_type_name"])
            ?? jsonString(raw["snapshot_gpu_alias_name"])
            ?? jsonString(raw["gpu_name"])
            ?? jsonString(raw["gpu_type"])
            ?? "GPU"
        let gpuCount = jsonInt(raw["req_gpu_amount"])
            ?? jsonInt(raw["gpu_num"])
            ?? jsonInt(raw["gpu_amount"])
            ?? 1
        let regionSign = jsonString(raw["region_sign"])
            ?? jsonString(raw["region"])
            ?? ""
        let regionName = jsonString(raw["region_name"])
            ?? jsonString(raw["region_alias"])
            ?? ""
        let machineID = jsonString(raw["machine_id"])
            ?? jsonString(raw["machine_alias"])
            ?? ""

        let usage = raw["usage_info"] as? [String: Any]
        let expandDataDisk = jsonInt64(raw["expand_data_disk_size"])
        let systemTotal = jsonInt64(raw["root_fs_total_size"])
            ?? jsonInt64(usage?["root_fs_total_size"])
        let systemUsed = jsonInt64(raw["root_fs_used_size"])
            ?? jsonInt64(usage?["root_fs_used_size"])
        let dataTotal = jsonInt64(usage?["data_disk_total_size"])
            ?? expandDataDisk.map { baseDataDiskBytes + $0 }
        let dataUsed = jsonInt64(usage?["data_disk_used_size"])
        let memoryTotal = jsonInt64(usage?["mem_limit"])
            ?? jsonInt64(raw["mem_limit"])
            ?? jsonInt64(raw["mem_limit_in_byte"])
        let memoryUsed = jsonInt64(usage?["mem_usage"])
            ?? jsonInt64(raw["mem_usage"])
        // rent_deadline 是 AutoDL 控制台展示的预计释放时间；expired_at 作为套餐到期兜底。
        let releaseDates = [
            jsonDate(raw["rent_deadline"]),
            jsonDate(raw["expired_at"])
        ].compactMap { $0 }
        let releaseAt = releaseDates.min()

        return AutoDLInstance(
            id: uuid,
            name: name,
            rawStatus: status,
            regionName: regionName,
            regionSign: regionSign,
            gpuName: gpuName,
            gpuCount: max(gpuCount, 1),
            machineID: machineID,
            chargeType: jsonString(raw["charge_type"]) ?? "",
            startedAt: jsonDate(raw["started_at"]),
            statusAt: jsonDate(raw["status_at"]) ?? jsonDate(raw["updated_at"]),
            sshCommand: jsonString(raw["ssh_command"]),
            rootPassword: jsonString(raw["root_password"]),
            jupyterDomain: jsonString(raw["jupyter_domain"]),
            systemDiskTotal: systemTotal,
            systemDiskUsed: systemUsed,
            dataDiskTotal: dataTotal,
            dataDiskUsed: dataUsed,
            diskExpandAvailable: jsonInt64(raw["disk_expand_available"]),
            memoryTotal: memoryTotal,
            memoryUsed: memoryUsed,
            releaseAt: releaseAt
        )
    }

    private static let baseDataDiskBytes: Int64 = 50 * 1_073_741_824
}

struct GPUStock: Equatable {
    let idleGPUs: Int
    let totalGPUs: Int?
    let machineID: String
    let gpuName: String
    let requiredGPUs: Int
    let checkedAt: Date
    let machineFound: Bool

    var isAvailable: Bool {
        machineFound && idleGPUs > 0 && idleGPUs >= requiredGPUs
    }

    var occupiedGPUs: Int? {
        guard let totalGPUs else { return nil }
        return max(0, totalGPUs - idleGPUs)
    }

    var availableGPUSlots: Int? {
        guard machineFound else { return nil }
        return idleGPUs
    }
}

struct GPUStockParseResult {
    let idleGPUs: Int
    let totalGPUs: Int?
    let machineFound: Bool
}

struct AccountBalance: Equatable {
    let cash: Double
    let blocked: Double
    let voucher: Double
    let paymentMethod: String?
    let fetchedAt: Date

    var available: Double {
        max(0, cash) + max(0, voucher)
    }

    var formattedAvailable: String {
        Self.currency(available)
    }

    var formattedCash: String {
        Self.currency(cash)
    }

    var formattedVoucher: String {
        Self.currency(voucher)
    }

    var formattedBlocked: String {
        Self.currency(blocked)
    }

    static func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "¥" + (formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value))
    }
}

enum BillType: String, Equatable {
    case charge
    case refund
    case recharge
    case withdraw

    var symbol: String {
        switch self {
        case .charge: return "bolt.fill"
        case .refund: return "arrow.uturn.backward"
        case .recharge: return "plus.circle.fill"
        case .withdraw: return "arrow.up.right.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .charge: return AppTheme.aqua
        case .refund: return AppTheme.mint
        case .recharge: return AppTheme.mint
        case .withdraw: return AppTheme.amber
        }
    }

    var isOutflow: Bool {
        self == .charge || self == .withdraw
    }
}

struct BillRecord: Identifiable, Equatable {
    let id: String
    let createdAt: Date
    let type: String
    let amount: Double
    let payByBalance: Double
    let payByVoucher: Double
    let balanceAfter: Double?
    let gpuType: String?
    let regionName: String?
    let machineID: String?
    let chargeDuration: Int?
    let chargeFrom: Date?
    let originPrice: Double?
    let discountAmount: Double

    var billType: BillType {
        BillType(rawValue: type.lowercased()) ?? .charge
    }

    var effectiveDate: Date {
        chargeFrom ?? createdAt
    }

    var signedAmountLabel: String {
        "\(billType.isOutflow ? "-" : "+")\(AccountBalance.currency(amount))"
    }

    var title: String {
        switch billType {
        case .charge:
            if let gpuType, !gpuType.isEmpty {
                if let regionName, !regionName.isEmpty {
                    return "\(gpuType) · \(regionName)"
                }
                return gpuType
            }
            return "GPU 消费"
        case .refund:
            return "账单退款"
        case .recharge:
            return "账户充值"
        case .withdraw:
            return "账户提现"
        }
    }

    var subtitle: String {
        let base = AppFormat.billDayTime.string(from: effectiveDate)
        if let durationLabel {
            return "\(base) · \(durationLabel)"
        }
        return base
    }

    var durationLabel: String? {
        guard let chargeDuration, chargeDuration > 0 else { return nil }
        if chargeDuration >= 3600 {
            let hours = chargeDuration / 3600
            let minutes = (chargeDuration % 3600) / 60
            return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分"
        }
        if chargeDuration >= 60 { return "\(chargeDuration / 60) 分钟" }
        return "\(chargeDuration) 秒"
    }

    var detailHelp: String {
        var parts: [String] = []
        if payByBalance > 0 {
            parts.append("余额支付 \(AccountBalance.currency(payByBalance))")
        }
        if payByVoucher > 0 {
            parts.append("代金券 \(AccountBalance.currency(payByVoucher))")
        }
        if let originPrice, discountAmount > 0 {
            parts.append("原价 \(AccountBalance.currency(originPrice)) · 优惠 \(AccountBalance.currency(discountAmount))")
        }
        if let balanceAfter {
            parts.append("支付后余额 \(AccountBalance.currency(balanceAfter))")
        }
        if let machineID, !machineID.isEmpty {
            parts.append("主机 \(machineID)")
        }
        return parts.joined(separator: " · ")
    }

    static func parse(_ raw: [String: Any]) -> BillRecord? {
        guard let id = jsonString(raw["uuid"]) ?? jsonInt(raw["id"]).map(String.init) else {
            return nil
        }
        let details = raw["details"] as? [String: Any]
        let discount = raw["discount_detail"] as? [String: Any]

        return BillRecord(
            id: id,
            createdAt: jsonDate(raw["created_at"]) ?? jsonDate(raw["confirm_at"]) ?? Date(),
            type: jsonString(raw["bill_type"]) ?? "charge",
            amount: max(0, (jsonDouble(raw["asset"]) ?? 0) / 1000),
            payByBalance: (jsonDouble(raw["pay_by_balance"]) ?? 0) / 1000,
            payByVoucher: (jsonDouble(raw["pay_by_voucher"]) ?? 0) / 1000,
            balanceAfter: jsonDouble(raw["balance"]).map { $0 / 1000 },
            gpuType: jsonString(details?["gpu_type"]),
            regionName: jsonString(details?["region_name"]) ?? jsonString(details?["region_sign"]),
            machineID: jsonString(details?["machine_id"]),
            chargeDuration: jsonInt(details?["charge_duration"]),
            chargeFrom: jsonDate(details?["charge_from"]),
            originPrice: jsonDouble(discount?["origin_price"]).map { $0 / 1000 },
            discountAmount: (jsonDouble(discount?["discount_sum"]) ?? 0) / 1000
        )
    }
}

struct DailySpend: Identifiable, Equatable {
    let date: Date
    let amount: Double

    var id: Date { date }
}

struct ConsumptionSlice: Identifiable, Equatable {
    let id: String
    let label: String
    let amount: Double
}

struct BillingSnapshot: Equatable {
    let records: [BillRecord]
    let fetchedAt: Date

    var chargeRecords: [BillRecord] {
        records.filter { $0.billType == .charge }
    }

    func netSpend(on day: Date) -> Double {
        let calendar = AppTime.calendar
        let net = records.reduce(0.0) { partial, record in
            guard calendar.isDate(record.effectiveDate, inSameDayAs: day) else { return partial }
            switch record.billType {
            case .charge: return partial + record.amount
            case .refund: return partial - record.amount
            default: return partial
            }
        }
        return max(0, net)
    }

    func netSpend(since start: Date) -> Double {
        let net = records.reduce(0.0) { partial, record in
            guard record.effectiveDate >= start else { return partial }
            switch record.billType {
            case .charge: return partial + record.amount
            case .refund: return partial - record.amount
            default: return partial
            }
        }
        return max(0, net)
    }

    func dailySeries(days: Int) -> [DailySpend] {
        let calendar = AppTime.calendar
        let end = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            return DailySpend(date: day, amount: netSpend(on: day))
        }
    }

    func totalSpend(days: Int) -> Double {
        dailySeries(days: days).reduce(0) { $0 + $1.amount }
    }

    var todaySpend: Double {
        totalSpend(days: 1)
    }

    var last7Spend: Double {
        totalSpend(days: 7)
    }

    var monthSpend: Double {
        let calendar = AppTime.calendar
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return netSpend(since: start)
    }

    var averageDailySpend: Double {
        last7Spend / 7
    }

    func estimatedDaysRemaining(balance: Double?) -> Int? {
        guard let balance, balance > 0, averageDailySpend > 0.01 else { return nil }
        return max(0, Int(balance / averageDailySpend))
    }

    func gpuConsumption(days: Int = 30) -> [ConsumptionSlice] {
        let calendar = AppTime.calendar
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return []
        }
        var totals: [String: Double] = [:]
        for record in chargeRecords where record.effectiveDate >= start {
            let key = record.gpuType?.isEmpty == false ? record.gpuType! : "其他消费"
            totals[key, default: 0] += record.amount
        }
        return totals
            .map { ConsumptionSlice(id: $0.key, label: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    var recentRecords: [BillRecord] {
        Array(records.sorted { $0.createdAt > $1.createdAt }.prefix(12))
    }
}

enum ActivityKind: Equatable {
    case info
    case success
    case warning
    case error

    var symbol: String {
        switch self {
        case .info: return "waveform.path.ecg"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

struct ActivityEvent: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let kind: ActivityKind
    let title: String
    let detail: String

    init(kind: ActivityKind, title: String, detail: String = "") {
        self.id = UUID()
        self.date = Date()
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id: UUID
    let kind: ActivityKind
    let title: String
    let message: String

    init(kind: ActivityKind, title: String, message: String) {
        self.id = UUID()
        self.kind = kind
        self.title = title
        self.message = message
    }
}

enum AutoDLError: LocalizedError {
    case unauthorized
    case http(status: Int)
    case api(code: String, message: String)
    case invalidResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "登录状态已失效，请重新登录 AutoDL"
        case .http(let status):
            return "AutoDL 服务返回 HTTP \(status)"
        case .api(_, let message):
            return message.isEmpty ? "AutoDL 接口请求失败" : message
        case .invalidResponse:
            return "无法解析 AutoDL 返回的数据"
        case .network(let message):
            return "网络请求失败：\(message)"
        }
    }

    var isAuthFailure: Bool {
        if case .unauthorized = self { return true }
        if case .api(let code, let message) = self {
            return code == "AuthorizeFailed"
                || code == "Unauthorized"
                || message.contains("登录超时")
                || message.contains("重新登录")
        }
        return false
    }
}

func jsonString(_ value: Any?) -> String? {
    if let string = value as? String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return nil
}

func jsonInt(_ value: Any?) -> Int? {
    if let int = value as? Int { return int }
    if let number = value as? NSNumber { return number.intValue }
    if let string = value as? String { return Int(string) }
    if let double = value as? Double { return Int(double) }
    return nil
}

func jsonInt64(_ value: Any?) -> Int64? {
    if let int = value as? Int64 { return int }
    if let number = value as? NSNumber { return number.int64Value }
    if let string = value as? String { return Int64(string) }
    return nil
}

func jsonDouble(_ value: Any?) -> Double? {
    if let double = value as? Double { return double }
    if let number = value as? NSNumber { return number.doubleValue }
    if let string = value as? String {
        let cleaned = string.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }
    return nil
}

func jsonBool(_ value: Any?) -> Bool? {
    if let bool = value as? Bool { return bool }
    if let number = value as? NSNumber { return number.boolValue }
    if let string = value as? String {
        if string == "true" { return true }
        if string == "false" { return false }
    }
    return nil
}

func jsonDate(_ value: Any?) -> Date? {
    if let dict = value as? [String: Any] {
        if jsonBool(dict["Valid"]) == false { return nil }
        return jsonDate(dict["Time"])
    }
    guard let string = value as? String, !string.isEmpty else { return nil }

    let isoFractional = ISO8601DateFormatter()
    isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoFractional.date(from: string) { return date }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: string) { return date }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.date(from: string)
}
