import Combine
import Foundation
import SwiftUI
import UserNotifications

enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard
    case instances
    case billing
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "监控台"
        case .instances: return "我的实例"
        case .billing: return "账单"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "dot.radiowaves.left.and.right"
        case .instances: return "square.stack.3d.up.fill"
        case .billing: return "chart.bar.xaxis"
        case .settings: return "slider.horizontal.3"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var phase: SessionPhase = .checking
    @Published var selectedSection: SidebarSection = .dashboard
    @Published private(set) var instances: [AutoDLInstance] = []
    @Published private(set) var selectedInstanceID: String?
    @Published private(set) var stock: GPUStock?
    @Published private(set) var balance: AccountBalance?
    @Published private(set) var balanceError: String?
    @Published private(set) var billing: BillingSnapshot?
    @Published private(set) var billingError: String?
    @Published private(set) var isBillingLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var activity: [ActivityEvent] = []
    @Published private(set) var isLoggingIn = false
    @Published var loginError: String?
    @Published private(set) var actionInstanceID: String?
    @Published private(set) var isAutoStarting = false
    @Published private(set) var autoStartEnabled: Bool
    @Published private(set) var pollInterval: TimeInterval
    @Published private(set) var lowBalanceThreshold: Double
    @Published private(set) var fontScale: Double
    @Published private(set) var tokenHint = ""
    @Published private(set) var signedInAt: Date?
    @Published var toast: ToastMessage?

    let notifications = NotificationService.shared

    private let defaults = UserDefaults.standard
    private var token: String?
    private var monitoringTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var gpuWasAvailable = false
    private var didNotifyForAvailability = false
    private var didNotifyForLowBalance = false
    private var lastAutoAttemptAt: Date?
    private var consecutiveErrors = 0

    private enum DefaultsKey {
        static let selectedInstance = "hunao.selectedInstanceUUID"
        static let autoStart = "hunao.autoStartEnabled"
        static let pollInterval = "hunao.pollIntervalSeconds"
        static let lowBalanceThreshold = "hunao.lowBalanceThreshold"
        static let fontScale = "hunao.fontScale"
    }

    var isLowBalance: Bool {
        guard let balance else { return false }
        return balance.available < lowBalanceThreshold
    }

    var balanceLabel: String {
        balance?.formattedAvailable ?? "—"
    }

    var selectedInstance: AutoDLInstance? {
        guard let selectedInstanceID else { return nil }
        return instances.first { $0.id == selectedInstanceID }
    }

    var runningCount: Int {
        instances.filter { $0.state == .running }.count
    }

    var autoStartSubtitle: String {
        if autoStartEnabled {
            return selectedInstance?.state == .stopped
                ? "守候空闲卡，出现即开机"
                : "等待实例关机后接管"
        }
        return "只提醒，不自动开机"
    }

    var availabilityHeadline: String {
        guard let instance = selectedInstance else { return "等待选择实例" }
        guard let stock else {
            return lastError == nil ? "正在读取显卡状态" : "显卡状态暂不可用"
        }
        if instance.state == .running {
            return "实例正在使用 GPU"
        }
        if instance.state == .starting {
            return "实例正在启动"
        }
        if instance.state == .stopping {
            return "实例正在关机"
        }
        if stock.isAvailable {
            return "发现空闲显卡"
        }
        if !stock.machineFound {
            return "目标主机暂未放出空卡"
        }
        return "正在等待空闲显卡"
    }

    var availabilityCaption: String {
        guard let instance = selectedInstance else {
            return "先在 AutoDL 创建一个实例"
        }
        guard let stock else {
            return "刷新间隔 \(Int(pollInterval)) 秒"
        }
        if stock.isAvailable {
            return autoStartEnabled ? "自动开机已就绪" : "自动开机已关闭，仅发送提醒"
        }
        if !stock.machineFound {
            return "目标主机 \(instance.machineID.isEmpty ? "ID 缺失" : instance.machineID) 暂无空闲卡"
        }
        return "已监测目标主机 · \(Int(pollInterval)) 秒刷新"
    }

    var nextCheckDate: Date? {
        guard let lastUpdated else { return nil }
        return lastUpdated.addingTimeInterval(pollInterval)
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.autoStart) == nil {
            defaults.set(false, forKey: DefaultsKey.autoStart)
        }
        autoStartEnabled = defaults.bool(forKey: DefaultsKey.autoStart)

        let storedInterval = defaults.double(forKey: DefaultsKey.pollInterval)
        pollInterval = (8...120).contains(storedInterval) ? storedInterval : 15

        let storedThreshold = defaults.double(forKey: DefaultsKey.lowBalanceThreshold)
        lowBalanceThreshold = (1...10_000).contains(storedThreshold) ? storedThreshold : 20

        let storedScale = defaults.double(forKey: DefaultsKey.fontScale)
        fontScale = (0.85...1.3).contains(storedScale) ? storedScale : 1.0

        selectedInstanceID = defaults.string(forKey: DefaultsKey.selectedInstance)

        if let savedToken = TokenStore.loadToken() {
            token = savedToken
            tokenHint = Self.maskedToken(savedToken)
            phase = .checking
            Task { await bootstrapWithSavedToken() }
        } else {
            phase = .loggedOut
        }
    }

    // MARK: - Session

    private func bootstrapWithSavedToken() async {
        guard let token else {
            phase = .loggedOut
            return
        }
        let api = AutoDLAPI(token: token)
        do {
            let list = try await api.fetchInstances()
            phase = .signedIn
            signedInAt = Date()
            applyInstances(list)
            addActivity(
                kind: .success,
                title: "已自动连接 AutoDL",
                detail: list.isEmpty ? "账号下暂无实例" : "正在守护 \(list.count) 个实例"
            )
            notifications.activate()
            requestNotificationPermissionIfNeeded()
            startMonitoring(immediately: true)
        } catch let error as AutoDLError where error.isAuthFailure {
            expireSession(reason: error.localizedDescription)
        } catch {
            phase = .signedIn
            signedInAt = Date()
            lastError = error.localizedDescription
            addActivity(kind: .error, title: "首次同步失败", detail: error.localizedDescription)
            notifications.activate()
            requestNotificationPermissionIfNeeded()
            startMonitoring(immediately: true)
        }
    }

    func signIn(token rawToken: String) async {
        let candidate = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !isLoggingIn else { return }

        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }

        let api = AutoDLAPI(token: candidate)
        do {
            let list = try await api.fetchInstances()
            let saved = TokenStore.saveToken(candidate)
            token = candidate
            tokenHint = Self.maskedToken(candidate)
            phase = .signedIn
            signedInAt = Date()
            loginError = nil
            lastError = nil
            applyInstances(list)
            addActivity(
                kind: .success,
                title: "登录成功",
                detail: saved ? "Token 已保存到本机受保护文件" : "Token 已在本次运行中生效"
            )
            if list.isEmpty {
                addActivity(kind: .info, title: "账号下暂无实例", detail: "请先在 AutoDL 创建实例")
            }
            notifications.activate()
            requestNotificationPermissionIfNeeded()
            startMonitoring(immediately: true)
        } catch let error as AutoDLError where error.isAuthFailure {
            loginError = "Token 无效或已过期，请重新扫码或登录"
        } catch {
            loginError = error.localizedDescription
        }
    }

    func logout() {
        monitoringTask?.cancel()
        monitoringTask = nil
        token = nil
        tokenHint = ""
        TokenStore.deleteToken()
        phase = .loggedOut
        signedInAt = nil
        instances = []
        selectedInstanceID = nil
        stock = nil
        lastUpdated = nil
        lastError = nil
        loginError = nil
        isRefreshing = false
        activity = []
        balance = nil
        balanceError = nil
        billing = nil
        billingError = nil
        isBillingLoading = false
        gpuWasAvailable = false
        didNotifyForAvailability = false
        didNotifyForLowBalance = false
        lastAutoAttemptAt = nil
        defaults.removeObject(forKey: DefaultsKey.selectedInstance)
        notifications.activate()
    }

    private func expireSession(reason: String) {
        monitoringTask?.cancel()
        monitoringTask = nil
        token = nil
        tokenHint = ""
        TokenStore.deleteToken()
        phase = .loggedOut
        signedInAt = nil
        stock = nil
        balance = nil
        balanceError = nil
        billing = nil
        billingError = nil
        isBillingLoading = false
        didNotifyForLowBalance = false
        lastUpdated = nil
        isRefreshing = false
        loginError = reason
        addActivity(kind: .error, title: "登录已失效", detail: reason)
        presentToast(kind: .error, title: "登录已失效", message: "请重新连接 AutoDL")
    }

    // MARK: - Monitoring

    private func startMonitoring(immediately: Bool) {
        monitoringTask?.cancel()
        monitoringTask = Task { [weak self] in
            guard let self else { return }
            if immediately {
                await self.refreshAll()
            }
            while !Task.isCancelled {
                let interval = max(self.pollInterval, 8)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                await self.refreshAll()
            }
        }
    }

    func refreshNow() {
        Task { await refreshAll(userInitiated: true) }
    }

    private func refreshAll(userInitiated: Bool = false) async {
        guard phase == .signedIn, let token else { return }
        guard !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        let api = AutoDLAPI(token: token)
        do {
            let list = try await api.fetchInstances()
            guard self.token == token, phase == .signedIn else { return }

            applyInstances(list)
            lastError = nil
            consecutiveErrors = 0

            do {
                let latestBalance = try await api.fetchBalance()
                guard self.token == token, phase == .signedIn else { return }
                balance = latestBalance
                balanceError = nil
                evaluateBalanceAlert()
            } catch let error as AutoDLError where error.isAuthFailure {
                expireSession(reason: error.localizedDescription)
                return
            } catch {
                balanceError = error.localizedDescription
            }

            guard let instance = selectedInstance else {
                stock = nil
                lastUpdated = Date()
                return
            }

            do {
                let latestStock = try await api.fetchGPUStock(for: instance)
                guard self.token == token, phase == .signedIn else { return }
                self.stock = latestStock
                self.lastUpdated = Date()
                self.evaluateStock(latestStock, for: instance)
            } catch let error as AutoDLError where error.isAuthFailure {
                expireSession(reason: error.localizedDescription)
                return
            } catch {
                lastError = "显卡状态同步失败：\(error.localizedDescription)"
                stock = nil
                lastUpdated = Date()
                registerFailure(message: lastError ?? "")
            }
        } catch let error as AutoDLError where error.isAuthFailure {
            expireSession(reason: error.localizedDescription)
        } catch {
            lastError = error.localizedDescription
            registerFailure(message: error.localizedDescription)
            if userInitiated {
                presentToast(kind: .error, title: "同步失败", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Billing

    func refreshBilling(force: Bool = false) {
        Task { await loadBilling(force: force) }
    }

    private func loadBilling(force: Bool) async {
        guard phase == .signedIn, let token, !isBillingLoading else { return }
        if !force, let billing, Date().timeIntervalSince(billing.fetchedAt) < 120 { return }

        isBillingLoading = true
        defer { isBillingLoading = false }

        let calendar = AppTime.calendar
        let end = Date()
        let start = calendar.date(
            byAdding: .day,
            value: -35,
            to: calendar.startOfDay(for: end)
        ) ?? end

        do {
            let records = try await AutoDLAPI(token: token).fetchBills(from: start, to: end)
            guard self.token == token, phase == .signedIn else { return }
            billing = BillingSnapshot(records: records, fetchedAt: Date())
            billingError = nil
        } catch let error as AutoDLError where error.isAuthFailure {
            expireSession(reason: error.localizedDescription)
        } catch {
            guard self.token == token, phase == .signedIn else { return }
            billingError = error.localizedDescription
        }
    }

    private func registerFailure(message: String) {
        consecutiveErrors += 1
        if consecutiveErrors == 1 || consecutiveErrors % 10 == 0 {
            addActivity(kind: .error, title: "监控同步异常", detail: message)
        }
    }

    private func applyInstances(_ list: [AutoDLInstance]) {
        instances = list
        let previousSelection = selectedInstanceID

        var next: AutoDLInstance?
        if let stored = defaults.string(forKey: DefaultsKey.selectedInstance) {
            next = list.first { $0.id == stored }
        }
        if next == nil, let previousSelection {
            next = list.first { $0.id == previousSelection }
        }
        if next == nil {
            next = list.first
        }

        selectedInstanceID = next?.id
        if let id = next?.id {
            defaults.set(id, forKey: DefaultsKey.selectedInstance)
        }

        if previousSelection != next?.id {
            stock = nil
            lastUpdated = nil
            resetAvailabilityEpisode()
            lastAutoAttemptAt = nil
        }
    }

    func selectInstance(_ id: String) {
        guard selectedInstanceID != id, instances.contains(where: { $0.id == id }) else { return }
        selectedInstanceID = id
        defaults.set(id, forKey: DefaultsKey.selectedInstance)
        stock = nil
        lastUpdated = nil
        lastError = nil
        resetAvailabilityEpisode()
        lastAutoAttemptAt = nil
        if let instance = selectedInstance {
            addActivity(kind: .info, title: "已切换监控目标", detail: "\(instance.name) · \(instance.gpuName)")
        }
        Task { await refreshAll(userInitiated: true) }
    }

    private func resetAvailabilityEpisode() {
        gpuWasAvailable = false
        didNotifyForAvailability = false
    }

    private func evaluateStock(_ latestStock: GPUStock, for instance: AutoDLInstance) {
        let available = latestStock.isAvailable
        let isPoweredOff = instance.state.isPoweredOff

        if available && !gpuWasAvailable {
            addActivity(
                kind: .warning,
                title: "发现空闲显卡",
                detail: "\(instance.machineID) · \(latestStock.idleGPUs) 张 \(instance.gpuName) 空闲"
            )
            if autoStartEnabled {
                addActivity(kind: .info, title: "自动开机已触发", detail: "正在尝试抢占空闲 GPU")
            }
        }

        gpuWasAvailable = available
        if !available {
            didNotifyForAvailability = false
            return
        }

        guard isPoweredOff else { return }

        if autoStartEnabled {
            Task { await attemptAutoPowerOn(instance: instance, stock: latestStock) }
        } else if !didNotifyForAvailability {
            didNotifyForAvailability = true
            notifyGPUAvailable(instance: instance, stock: latestStock)
        }
    }

    private func notifyGPUAvailable(instance: AutoDLInstance, stock: GPUStock) {
        let title = "发现空闲 GPU"
        let body = "\(instance.name) 所在主机有 \(stock.idleGPUs) 张 \(instance.gpuName) 空闲，自动开机已关闭。"
        addActivity(kind: .warning, title: "已发送空闲提醒", detail: body)
        presentToast(kind: .warning, title: title, message: body)
        Task {
            await notifications.send(
                title: title,
                body: body,
                identifier: "hunao.gpu.available.\(instance.id)"
            )
        }
    }

    // MARK: - Automation

    func setAutoStart(_ enabled: Bool) {
        guard autoStartEnabled != enabled else { return }
        autoStartEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.autoStart)

        if enabled {
            addActivity(kind: .info, title: "自动开机已开启", detail: "检测到空闲显卡后自动抢占")
            if let instance = selectedInstance,
               instance.state.isPoweredOff,
               let stock,
               stock.isAvailable {
                Task { await attemptAutoPowerOn(instance: instance, stock: stock) }
            }
        } else {
            addActivity(kind: .info, title: "自动开机已关闭", detail: "之后仅在有卡空闲时提醒")
            if let instance = selectedInstance,
               instance.state.isPoweredOff,
               let stock,
               stock.isAvailable,
               !didNotifyForAvailability {
                didNotifyForAvailability = true
                notifyGPUAvailable(instance: instance, stock: stock)
            }
        }
    }

    func setPollInterval(_ seconds: TimeInterval) {
        let normalized = min(max(seconds, 8), 120)
        guard pollInterval != normalized else { return }
        pollInterval = normalized
        defaults.set(normalized, forKey: DefaultsKey.pollInterval)
        addActivity(kind: .info, title: "刷新间隔已调整", detail: "每 \(Int(normalized)) 秒检查一次")
        if phase == .signedIn {
            startMonitoring(immediately: false)
        }
    }

    func setLowBalanceThreshold(_ value: Double) {
        let normalized = min(max(value, 1), 10_000)
        guard abs(normalized - lowBalanceThreshold) > 0.001 else { return }
        lowBalanceThreshold = normalized
        defaults.set(normalized, forKey: DefaultsKey.lowBalanceThreshold)
        addActivity(
            kind: .info,
            title: "余额提醒阈值已更新",
            detail: "可用余额低于 \(AccountBalance.currency(normalized)) 时提醒"
        )

        guard let balance else { return }
        if balance.available >= normalized {
            didNotifyForLowBalance = false
        } else {
            evaluateBalanceAlert()
        }
    }

    func setFontScale(_ value: Double) {
        let stepped = (min(max(value, 0.85), 1.3) * 20).rounded() / 20
        guard abs(stepped - fontScale) > 0.001 else { return }
        fontScale = stepped
        defaults.set(stepped, forKey: DefaultsKey.fontScale)
    }

    private func evaluateBalanceAlert() {
        guard let balance else { return }
        guard balance.available < lowBalanceThreshold else {
            didNotifyForLowBalance = false
            return
        }
        guard !didNotifyForLowBalance else { return }
        didNotifyForLowBalance = true

        let title = "余额不足提醒"
        let voucherNote = balance.voucher > 0 ? "（含代金券 \(balance.formattedVoucher)）" : ""
        let body = "AutoDL 可用余额 \(balance.formattedAvailable)\(voucherNote)，已低于 \(AccountBalance.currency(lowBalanceThreshold))，请及时充值以免影响自动开机。"
        addActivity(kind: .warning, title: title, detail: body)
        presentToast(kind: .warning, title: title, message: body)
        Task {
            await notifications.send(
                title: title,
                body: body,
                identifier: "hunao.balance.low"
            )
        }
    }

    private func attemptAutoPowerOn(instance: AutoDLInstance, stock: GPUStock) async {
        guard autoStartEnabled, phase == .signedIn, !isAutoStarting else { return }
        guard instance.id == selectedInstanceID else { return }
        guard instance.state.isPoweredOff else { return }
        guard stock.isAvailable else { return }
        if let lastAutoAttemptAt, Date().timeIntervalSince(lastAutoAttemptAt) < 60 {
            return
        }

        guard let token else { return }
        isAutoStarting = true
        lastAutoAttemptAt = Date()
        defer { isAutoStarting = false }

        do {
            try await AutoDLAPI(token: token).powerOn(instanceUUID: instance.id)
            let title = "自动开机成功"
            let detail = "\(instance.name) 正在启动，已抢占 \(stock.idleGPUs) 张空闲 \(instance.gpuName)"
            addActivity(kind: .success, title: title, detail: detail)
            presentToast(kind: .success, title: title, message: detail)
            await notifications.send(
                title: title,
                body: detail,
                identifier: "hunao.autostart.success.\(instance.id)"
            )
            let delay: UInt64 = 2_500_000_000
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                await self?.refreshAll()
            }
        } catch let error as AutoDLError where error.isAuthFailure {
            expireSession(reason: error.localizedDescription)
        } catch {
            let detail = error.localizedDescription
            addActivity(kind: .error, title: "自动开机失败", detail: detail)
            presentToast(kind: .error, title: "自动开机失败", message: detail)
        }
    }

    func powerOn(instance: AutoDLInstance) {
        Task { await performPowerAction(instance: instance, turnOn: true) }
    }

    func powerOff(instance: AutoDLInstance) {
        Task { await performPowerAction(instance: instance, turnOn: false) }
    }

    private func performPowerAction(instance: AutoDLInstance, turnOn: Bool) async {
        guard phase == .signedIn, actionInstanceID == nil, let token else { return }
        actionInstanceID = instance.id
        defer { actionInstanceID = nil }

        do {
            let api = AutoDLAPI(token: token)
            if turnOn {
                try await api.powerOn(instanceUUID: instance.id)
            } else {
                try await api.powerOff(instanceUUID: instance.id)
            }
            addActivity(
                kind: .success,
                title: turnOn ? "手动开机指令已发送" : "手动关机指令已发送",
                detail: instance.name
            )
            let delay: UInt64 = 2_000_000_000
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                await self?.refreshAll()
            }
        } catch let error as AutoDLError where error.isAuthFailure {
            expireSession(reason: error.localizedDescription)
        } catch {
            presentToast(kind: .error, title: turnOn ? "开机失败" : "关机失败", message: error.localizedDescription)
            addActivity(kind: .error, title: turnOn ? "开机失败" : "关机失败", detail: error.localizedDescription)
        }
    }

    // MARK: - Notifications

    func requestNotifications() {
        Task {
            await notifications.requestAuthorization()
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        Task {
            await notifications.refreshAuthorizationStatus()
            if notifications.authorizationStatus == .notDetermined {
                _ = await notifications.requestAuthorization()
            }
        }
    }

    func sendTestNotification() {
        Task {
            if notifications.authorizationStatus == .notDetermined {
                _ = await notifications.requestAuthorization()
            }
            let delivered = await notifications.sendTestNotification()
            if !delivered {
                presentToast(
                    kind: .warning,
                    title: "通知发送失败",
                    message: "请在系统设置中允许胡闹AutoDL发送通知"
                )
            } else if !notifications.alertsEnabled {
                presentToast(
                    kind: .warning,
                    title: "通知已送达",
                    message: "横幅提醒已关闭，请在系统设置中把通知样式改为「横幅」"
                )
            } else {
                presentToast(
                    kind: .info,
                    title: "测试通知已发送",
                    message: "如果没有看到横幅，请检查系统通知设置"
                )
            }
        }
    }

    func openNotificationSettings() {
        notifications.openSystemNotificationSettings()
    }

    // MARK: - UI helpers

    func addActivity(kind: ActivityKind, title: String, detail: String = "") {
        activity.insert(ActivityEvent(kind: kind, title: title, detail: detail), at: 0)
        if activity.count > 40 {
            activity = Array(activity.prefix(40))
        }
    }

    func presentToast(kind: ActivityKind, title: String, message: String) {
        let newToast = ToastMessage(kind: kind, title: title, message: message)
        toast = newToast
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.toast?.id == newToast.id {
                self?.toast = nil
            }
        }
    }

    func dismissToast(_ toast: ToastMessage) {
        if self.toast?.id == toast.id {
            self.toast = nil
        }
    }

    private static func maskedToken(_ token: String) -> String {
        guard token.count > 12 else { return "••••••••" }
        return "\(token.prefix(5))••••••\(token.suffix(4))"
    }
}
