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
            jupyterDomain: jsonString(raw["jupyter_domain"])
        )
    }
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
