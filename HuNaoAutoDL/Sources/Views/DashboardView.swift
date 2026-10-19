import AppKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var notifications = NotificationService.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                header

                if let error = model.lastError {
                    errorBanner(error)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(alignment: .top, spacing: 16) {
                    sentinelCard
                        .frame(maxWidth: .infinity, minHeight: 342)

                    VStack(spacing: 16) {
                        autoPowerCard
                            .frame(height: 163)
                        targetCard
                            .frame(height: 163)
                    }
                    .frame(width: 288)
                }

                resourceDeck

                HStack(alignment: .top, spacing: 16) {
                    activityCard
                        .frame(maxWidth: .infinity, minHeight: 228)

                    guardianCard
                        .frame(width: 288)
                        .frame(minHeight: 228)
                }
            }
            .padding(.bottom, 26)
        }
        .scrollIndicators(.never)
        .animation(.smooth(duration: 0.32), value: model.lastError)
        .animation(.smooth(duration: 0.32), value: model.stock)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 9) {
                    EyebrowLabel(text: "Command Center")
                    Rectangle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 22, height: 0.6)
                    Text(AppFormat.fullDate.string(from: Date()))
                        .scaledFont(size: 9.5, weight: .medium)
                        .foregroundStyle(AppTheme.textTertiary)
                }

                HStack(spacing: 10) {
                    Text("监控台")
                        .scaledFont(size: 27, weight: .bold, design: .rounded)
                        .foregroundStyle(AppTheme.textPrimary)
                        .tracking(-0.6)

                    StatusPill(
                        label: model.instances.isEmpty ? "等待实例" : "实时监控",
                        tint: model.instances.isEmpty ? AppTheme.amber : AppTheme.mint
                    )
                }

                Text("哎呀，这简直是胡！闹！")
                    .scaledFont(size: 11.5)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 8) {
                balanceChip

                HStack(spacing: 6) {
                    Circle()
                        .fill(model.isRefreshing ? AppTheme.amber : AppTheme.mint)
                        .frame(width: 5, height: 5)
                        .shadow(color: (model.isRefreshing ? AppTheme.amber : AppTheme.mint).opacity(0.8), radius: 4)
                    Text(model.isRefreshing ? "同步中" : "\(Int(model.pollInterval))s 刷新")
                        .scaledFont(size: 9.5, weight: .medium)
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.horizontal, 11)
                .frame(height: 32)
                .glassPanel(cornerRadius: 11, tint: .white)

                GlassIconButton(
                    symbol: "arrow.clockwise",
                    action: { model.refreshNow() },
                    isActive: model.isRefreshing,
                    help: "立即刷新"
                )
            }
        }
    }

    private var balanceChip: some View {
        HStack(spacing: 7) {
            Image(systemName: model.isLowBalance ? "exclamationmark.circle.fill" : "yensign.circle.fill")
                .scaledFont(size: 11, weight: .semibold)
                .foregroundStyle(model.isLowBalance ? AppTheme.amber : AppTheme.mint.opacity(0.88))

            VStack(alignment: .leading, spacing: 0) {
                Text("可用余额")
                    .scaledFont(size: 7, weight: .bold, design: .rounded)
                    .tracking(0.8)
                    .foregroundStyle(AppTheme.textTertiary)
                Text(model.balance == nil ? "同步中" : model.balanceLabel)
                    .scaledFont(size: 10.5, weight: .bold, design: .rounded)
                    .foregroundStyle(model.isLowBalance ? AppTheme.amber : AppTheme.textPrimary.opacity(0.90))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .glassPanel(cornerRadius: 11, tint: model.isLowBalance ? AppTheme.amber : .white)
        .help(balanceHelp)
    }

    private var balanceHelp: String {
        guard let balance = model.balance else {
            return "正在同步 AutoDL 账户余额"
        }
        return "现金 \(balance.formattedCash) · 代金券 \(balance.formattedVoucher) · 冻结 \(balance.formattedBlocked)"
    }

    private var sentinelCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    EyebrowLabel(text: "Live GPU Monitor", tint: AppTheme.aqua)
                    Text("GPU 空闲哨兵")
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Spacer()

                if let instance = model.selectedInstance {
                    StatusPill(
                        label: instance.state.label,
                        tint: instance.state.tint
                    )
                } else {
                    StatusPill(label: "未选择实例", tint: AppTheme.textSecondary)
                }
            }

            if let instance = model.selectedInstance {
                HStack(spacing: 22) {
                    GPUOrbitGauge(
                        idle: model.stock?.idleGPUs,
                        total: model.stock?.totalGPUs,
                        required: instance.gpuCount,
                        isAvailable: model.stock?.isAvailable == true,
                        isBusy: instance.state == .running || instance.state == .starting,
                        isLoading: model.isRefreshing && model.stock == nil
                    )
                    .frame(width: 152, height: 152)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.availabilityHeadline)
                            .scaledFont(size: 20, weight: .bold, design: .rounded)
                            .tracking(-0.4)
                            .foregroundStyle(
                                model.stock?.isAvailable == true
                                    ? AnyShapeStyle(AppTheme.accentGradient)
                                    : AnyShapeStyle(AppTheme.textPrimary)
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        HStack(spacing: 6) {
                            Text(instance.name)
                                .scaledFont(size: 11.5, weight: .semibold)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                            Circle().fill(AppTheme.textTertiary).frame(width: 2.5, height: 2.5)
                            Text(instance.gpuName)
                                .scaledFont(size: 10.5, weight: .medium)
                                .foregroundStyle(AppTheme.textTertiary)
                                .lineLimit(1)
                        }
                        .padding(.top, 5)

                        Text(model.availabilityCaption)
                            .scaledFont(size: 10)
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(2)
                            .padding(.top, 8)

                        Spacer(minLength: 12)

                        HStack(spacing: 8) {
                            MetaChip(
                                symbol: "mappin.and.ellipse",
                                label: instance.displayRegion
                            )
                            MetaChip(
                                symbol: "server.rack",
                                label: instance.machineID.isEmpty ? "主机未知" : instance.machineID
                            )
                        }

                        HStack(spacing: 8) {
                            MetaChip(
                                symbol: "cpu",
                                label: "\(instance.gpuCount) 卡 · \(instance.chargeLabel)"
                            )
                            MetaChip(
                                symbol: "clock",
                                label: "更新于 \(AppFormat.relative(model.lastUpdated))"
                            )
                        }
                        .padding(.top, 7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 12)

                Spacer(minLength: 12)

                gpuSlotStrip(instance: instance)
                    .padding(.top, 8)
            } else {
                EmptyStateView(
                    symbol: "rectangle.stack.badge.plus",
                    title: "还没有可监控的实例",
                    message: "请在 AutoDL 控制台创建实例，刷新后会出现在这里。"
                )
                .frame(height: 245)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(
            cornerRadius: 26,
            tint: model.stock?.isAvailable == true ? AppTheme.mint : AppTheme.aqua
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill((model.stock?.isAvailable == true ? AppTheme.mint : AppTheme.aqua).opacity(0.12))
                .frame(width: 190, height: 190)
                .blur(radius: 65)
                .offset(x: 80, y: -80)
                .allowsHitTesting(false)
        }
    }

    private func gpuSlotStrip(instance: AutoDLInstance) -> some View {
        let total = model.stock?.totalGPUs
        let slotCount = min(max(total ?? instance.gpuCount, 1), 12)
        let idle = model.stock.map { min($0.idleGPUs, slotCount) } ?? 0
        let hasStock = model.stock != nil

        return HStack(spacing: 8) {
            Text("GPU SLOTS")
                .scaledFont(size: 7.5, weight: .bold, design: .rounded)
                .tracking(1.2)
                .foregroundStyle(AppTheme.textTertiary)

            HStack(spacing: 4) {
                ForEach(0..<slotCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(
                            hasStock && index < idle
                                ? AnyShapeStyle(AppTheme.accentGradient)
                                : AnyShapeStyle(.white.opacity(0.08))
                        )
                        .frame(height: 6)
                        .frame(maxWidth: .infinity)
                        .shadow(
                            color: hasStock && index < idle ? AppTheme.mint.opacity(0.30) : .clear,
                            radius: 4,
                            y: 1
                        )
                }
            }
            .frame(maxWidth: 190)

            Text(hasStock ? "\(idle) FREE" : "待同步")
                .scaledFont(size: 7.5, weight: .bold, design: .rounded)
                .tracking(0.5)
                .foregroundStyle(hasStock ? AppTheme.mint.opacity(0.78) : AppTheme.textTertiary)
                .frame(width: 46, alignment: .trailing)
        }
    }

    private var resourceDeck: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    EyebrowLabel(text: "Runtime Resources", tint: AppTheme.violet)
                    Text("实例资源余量")
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Spacer()

                if let instance = model.selectedInstance {
                    StatusPill(label: instance.state.label, tint: instance.state.tint)
                } else {
                    StatusPill(label: "未选择实例", tint: AppTheme.textSecondary)
                }
            }

            if let instance = model.selectedInstance {
                HStack(alignment: .center, spacing: 24) {
                    ResourceOrbitGauge(
                        title: "剩余内存",
                        freeLabel: instance.memoryFreeLabel,
                        detail: instance.memoryTotal.map { "共 \(AppFormat.storage($0))" } ?? "待同步",
                        freeFraction: instance.memoryUsedFraction.map { 1 - $0 },
                        tint: AppTheme.violet
                    )
                    .help("\(instance.memoryDetailLabel) · 当前实例剩余可用内存")

                    ResourceOrbitGauge(
                        title: "剩余存储",
                        freeLabel: instance.storageFreeLabel,
                        detail: instance.storageTotalBytes.map { "共 \(AppFormat.storage($0))" } ?? "待同步",
                        freeFraction: instance.storageUsedFraction.map { 1 - $0 },
                        tint: AppTheme.aqua
                    )
                    .help("\(instance.storageDetailLabel) · 当前实例剩余可用存储")

                    Rectangle()
                        .fill(.white.opacity(0.07))
                        .frame(width: 0.6, height: 82)

                    VStack(alignment: .leading, spacing: 10) {
                        resourceDetailRow(
                            symbol: "memorychip",
                            title: "运行内存",
                            value: instance.memoryDetailLabel,
                            tint: AppTheme.violet
                        )
                        resourceDetailRow(
                            symbol: "internaldrive",
                            title: "磁盘空间",
                            value: instance.storageDetailLabel,
                            tint: AppTheme.aqua
                        )
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .scaledFont(size: 8, weight: .semibold)
                            Text("随每次刷新同步 · 每 \(Int(model.pollInterval)) 秒")
                                .scaledFont(size: 8.5, weight: .medium)
                        }
                        .foregroundStyle(AppTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 14)
            } else {
                EmptyStateView(
                    symbol: "gauge.with.dots.needle.33percent",
                    title: "暂无资源数据",
                    message: "选择实例后，这里会显示内存与存储的圆形余量仪表。"
                )
                .frame(height: 130)
            }
        }
        .padding(20)
        .glassPanel(cornerRadius: 24, tint: AppTheme.violet)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(AppTheme.violet.opacity(0.10))
                .frame(width: 170, height: 170)
                .blur(radius: 60)
                .offset(x: 76, y: -74)
                .allowsHitTesting(false)
        }
    }

    private func resourceDetailRow(
        symbol: String,
        title: String,
        value: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .scaledFont(size: 10, weight: .semibold)
                .foregroundStyle(tint.opacity(0.85))
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1.5) {
                Text(title)
                    .scaledFont(size: 8.5, weight: .medium)
                    .foregroundStyle(AppTheme.textTertiary)
                Text(value)
                    .scaledFont(size: 10.5, weight: .semibold)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
    }

    private var autoPowerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(
                            (model.autoStartEnabled ? AppTheme.mint : Color.white)
                                .opacity(model.autoStartEnabled ? 0.13 : 0.06)
                        )
                        .frame(width: 28, height: 28)
                    Image(systemName: "power")
                        .scaledFont(size: 11, weight: .bold)
                        .foregroundStyle(model.autoStartEnabled ? AppTheme.mint : AppTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    EyebrowLabel(
                        text: model.autoStartEnabled ? "Auto Pilot" : "Manual Watch",
                        tint: model.autoStartEnabled ? AppTheme.mint : AppTheme.textTertiary
                    )
                    Text("自动开机")
                        .scaledFont(size: 14.5, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Spacer()

                CustomSwitch(isOn: model.autoStartEnabled) {
                    model.setAutoStart(!model.autoStartEnabled)
                }
            }

            if model.isAutoStarting {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(AppTheme.mint)
                    Text("正在抢占空闲显卡…")
                        .scaledFont(size: 10.5, weight: .semibold)
                        .foregroundStyle(AppTheme.mint)
                }
                .padding(.top, 12)
            } else {
                Text(model.autoStartSubtitle)
                    .scaledFont(size: 10.5)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 10)
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                Circle()
                    .fill(model.autoStartEnabled ? AppTheme.mint : AppTheme.amber)
                    .frame(width: 4, height: 4)
                Text(
                    model.autoStartEnabled
                        ? "空闲即抢，成功后通知我"
                        : "关闭自动开机，有卡时提醒我"
                )
                .scaledFont(size: 9)
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(
            cornerRadius: 24,
            tint: model.autoStartEnabled ? AppTheme.mint : .white,
            interactive: true
        )
        .overlay(alignment: .topTrailing) {
            if model.autoStartEnabled {
                Circle()
                    .fill(AppTheme.mint.opacity(0.16))
                    .frame(width: 110, height: 110)
                    .blur(radius: 38)
                    .offset(x: 45, y: -40)
                    .allowsHitTesting(false)
            }
        }
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EyebrowLabel(text: "Active Target", tint: AppTheme.aqua)

                Spacer()

                Menu {
                    if model.instances.isEmpty {
                        Text("暂无实例")
                    } else {
                        ForEach(model.instances) { instance in
                            Button {
                                model.selectInstance(instance.id)
                            } label: {
                                if instance.id == model.selectedInstanceID {
                                    Label(instance.name, systemImage: "checkmark")
                                } else {
                                    Text(instance.name)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("切换")
                        Image(systemName: "chevron.down")
                            .scaledFont(size: 7.5, weight: .bold)
                    }
                    .scaledFont(size: 9.5, weight: .semibold)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.055), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(.white.opacity(0.07), lineWidth: 0.6)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.instances.isEmpty)
            }

            if let instance = model.selectedInstance {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(instance.name)
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        Text("\(instance.gpuName) · \(instance.displayRegion)")
                            .scaledFont(size: 9.5)
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(1)
                        Text("内存剩余 \(instance.memoryFreeLabel) · 存储剩余 \(instance.storageFreeLabel)")
                            .scaledFont(size: 8.5, weight: .medium)
                            .foregroundStyle(AppTheme.aqua.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .help("\(instance.memoryDetailLabel) · \(instance.storageDetailLabel)")
                    }

                    Spacer(minLength: 6)

                    StatusPill(label: instance.state.label, tint: instance.state.tint)
                }
                .padding(.top, 9)

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    Text(instance.machineID.isEmpty ? "主机待同步" : instance.machineID)
                        .scaledFont(size: 8.5, weight: .medium, design: .monospaced)
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)

                    Spacer()

                    powerButton(for: instance)
                }
            } else {
                Spacer()
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle")
                        .scaledFont(size: 12)
                    Text("前往 AutoDL 创建实例")
                        .scaledFont(size: 10.5, weight: .medium)
                }
                .foregroundStyle(AppTheme.textSecondary)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let url = URL(string: "https://www.autodl.com/console/instance/list") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(cornerRadius: 24, tint: AppTheme.aqua)
    }

    @ViewBuilder
    private func powerButton(for instance: AutoDLInstance) -> some View {
        let isActing = model.actionInstanceID == instance.id
        let disabled = isActing || instance.state.isBusy || instance.state == .unknown

        Button {
            if instance.state == .running {
                confirmStopAndPowerOff(instance)
            } else {
                model.powerOn(instance: instance)
            }
        } label: {
            HStack(spacing: 5) {
                if isActing {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: instance.state == .running ? "stop.fill" : "play.fill")
                        .scaledFont(size: 7.5, weight: .bold)
                }
                Text(
                    instance.state == .running
                        ? "关机"
                        : (instance.state.isBusy ? instance.state.label : "开机")
                )
            }
        }
        .buttonStyle(
            ActionButtonStyle(
                tint: instance.state == .running ? AppTheme.rose : AppTheme.mint,
                prominent: instance.state != .running
            )
        )
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private func confirmStopAndPowerOff(_ instance: AutoDLInstance) {
        let alert = NSAlert()
        alert.messageText = "关闭 \(instance.name)？"
        alert.informativeText = "关机后如果自动开机已开启，胡闹会在目标主机出现空闲卡时再次开机。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "关机")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            model.powerOff(instance: instance)
        }
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowLabel(text: "Live Activity", tint: AppTheme.violet)
                    Text("实时动态")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(AppTheme.mint)
                        .frame(width: 4, height: 4)
                    Text("\(model.activity.count) 条")
                        .scaledFont(size: 9, weight: .medium)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .padding(.bottom, 12)

            if model.activity.isEmpty {
                EmptyStateView(
                    symbol: "waveform.path.ecg",
                    title: "还没有监控动态",
                    message: "实例状态变化、空闲提醒和自动开机会记录在这里。"
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.activity.prefix(12))) { event in
                            ActivityRow(event: event)
                            if event.id != model.activity.prefix(12).last?.id {
                                Rectangle()
                                    .fill(.white.opacity(0.045))
                                    .frame(height: 0.6)
                                    .padding(.leading, 33)
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(cornerRadius: 24, tint: AppTheme.violet)
    }

    private var guardianCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowLabel(text: "Guardrails", tint: AppTheme.amber)
                    Text("守护设置")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                }
                Spacer()
                Image(systemName: "shield.lefthalf.filled")
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(AppTheme.amber.opacity(0.65))
            }

            VStack(spacing: 10) {
                GuardianRow(
                    symbol: "timer",
                    label: "检查频率",
                    value: "每 \(Int(model.pollInterval)) 秒",
                    tint: AppTheme.aqua
                )
                GuardianRow(
                    symbol: "yensign.circle.fill",
                    label: "账户余额",
                    value: model.isLowBalance ? "\(model.balanceLabel) · 偏低" : model.balanceLabel,
                    tint: model.isLowBalance ? AppTheme.amber : AppTheme.mint
                )
                GuardianRow(
                    symbol: notificationSymbol,
                    label: "系统通知",
                    value: notificationLabel,
                    tint: notificationTint
                )
                GuardianRow(
                    symbol: "key.fill",
                    label: "登录凭证",
                    value: "已存入本机",
                    tint: AppTheme.mint
                )
            }
            .padding(.top, 14)

            Spacer(minLength: 8)

            if notifications.authorizationStatus == .denied {
                Button {
                    model.openNotificationSettings()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bell.badge.fill")
                            .scaledFont(size: 9)
                        Text("开启系统通知")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ActionButtonStyle(tint: AppTheme.amber))
            } else {
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        model.selectedSection = .settings
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("调整守护参数")
                        Image(systemName: "arrow.up.right")
                            .scaledFont(size: 8, weight: .bold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ActionButtonStyle(tint: .white))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(cornerRadius: 24, tint: AppTheme.amber)
    }

    private var notificationSymbol: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional: return "bell.fill"
        case .denied: return "bell.slash.fill"
        case .notDetermined: return "bell.badge.fill"
        @unknown default: return "bell.fill"
        }
    }

    private var notificationLabel: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional: return "已开启"
        case .denied: return "已关闭"
        case .notDetermined: return "待授权"
        @unknown default: return "未知"
        }
    }

    private var notificationTint: Color {
        switch notifications.authorizationStatus {
        case .authorized, .provisional: return AppTheme.mint
        case .denied: return AppTheme.rose
        case .notDetermined: return AppTheme.amber
        @unknown default: return AppTheme.textTertiary
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .scaledFont(size: 11, weight: .semibold)
                .foregroundStyle(AppTheme.amber)
            Text(message)
                .scaledFont(size: 10.5, weight: .medium)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
            Spacer()
            Button("重试") { model.refreshNow() }
                .scaledFont(size: 10.5, weight: .semibold)
                .foregroundStyle(AppTheme.mint)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassPanel(cornerRadius: 14, tint: AppTheme.amber)
    }
}

private struct MetaChip: View {
    let symbol: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .scaledFont(size: 8, weight: .semibold)
                .foregroundStyle(AppTheme.textTertiary)
            Text(label)
                .scaledFont(size: 8.5, weight: .medium)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.04), in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
        }
    }
}

private struct GuardianRow: View {
    let symbol: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .scaledFont(size: 9, weight: .semibold)
                .foregroundStyle(tint.opacity(0.80))
                .frame(width: 17)
            Text(label)
                .scaledFont(size: 10, weight: .medium)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .scaledFont(size: 9.5, weight: .semibold)
                .foregroundStyle(AppTheme.textPrimary.opacity(0.82))
                .lineLimit(1)
        }
    }
}

private struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(event.kind.tint.opacity(0.10))
                    .frame(width: 23, height: 23)
                Image(systemName: event.kind.symbol)
                    .scaledFont(size: 9, weight: .semibold)
                    .foregroundStyle(event.kind.tint.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .scaledFont(size: 10.5, weight: .semibold)
                    .foregroundStyle(AppTheme.textPrimary.opacity(0.88))
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .scaledFont(size: 9)
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Text(AppFormat.time.string(from: event.date))
                .scaledFont(size: 8.5, weight: .medium, design: .monospaced)
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(.vertical, 8)
    }
}

private struct GPUOrbitGauge: View {
    let idle: Int?
    let total: Int?
    let required: Int
    let isAvailable: Bool
    let isBusy: Bool
    let isLoading: Bool

    @State private var orbit = false
    @State private var pulse = false

    private var progress: CGFloat {
        guard let idle else { return 0.035 }
        if let total, total > 0 {
            return max(0.035, min(CGFloat(idle) / CGFloat(total), 1))
        }
        return isAvailable ? 0.72 : 0.035
    }

    private var tint: Color {
        if isAvailable { return AppTheme.mint }
        if isBusy { return AppTheme.aqua }
        return .white.opacity(0.55)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            tint.opacity(isAvailable ? 0.18 : 0.07),
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 76
                    )
                )

            Circle()
                .stroke(.white.opacity(0.055), lineWidth: 10)
                .padding(6)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: isAvailable
                            ? [AppTheme.aqua.opacity(0.4), AppTheme.mint, AppTheme.mint]
                            : [Color.white.opacity(0.16), Color.white.opacity(0.5)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(6)
                .shadow(color: tint.opacity(isAvailable ? 0.55 : 0.10), radius: 9)
                .animation(.spring(response: 0.7, dampingFraction: 0.82), value: progress)

            Circle()
                .stroke(
                    tint.opacity(0.24),
                    style: StrokeStyle(lineWidth: 0.7, dash: [2, 7])
                )
                .padding(22)
                .rotationEffect(.degrees(orbit ? 360 : 0))

            Circle()
                .fill(tint)
                .frame(width: 3.5, height: 3.5)
                .offset(y: -61)
                .rotationEffect(.degrees(orbit ? 360 : 0))
                .opacity(isAvailable ? 0.9 : 0.25)
                .shadow(color: tint.opacity(0.8), radius: 4)

            VStack(spacing: 1) {
                Text(isLoading ? "..." : (idle.map(String.init) ?? "—"))
                    .scaledFont(size: 47, weight: .bold, design: .rounded)
                    .tracking(-2)
                    .foregroundStyle(
                        isAvailable
                            ? AnyShapeStyle(AppTheme.accentGradient)
                            : AnyShapeStyle(AppTheme.textPrimary.opacity(0.90))
                    )
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: idle)

                Text("空闲 GPU")
                    .scaledFont(size: 8.5, weight: .semibold)
                    .foregroundStyle(AppTheme.textSecondary)

                Text(total.map { "共 \($0) 卡" } ?? "目标主机")
                    .scaledFont(size: 7.5, weight: .medium)
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.top, 2)
            }
        }
        .frame(width: 152, height: 152)
        .onAppear {
            withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) {
                orbit = true
            }
        }
    }
}

private struct ResourceOrbitGauge: View {
    let title: String
    let freeLabel: String
    let detail: String
    let freeFraction: Double?
    let tint: Color

    @State private var orbit = false

    private var progress: CGFloat {
        guard let freeFraction else { return 0.035 }
        return CGFloat(max(0.035, min(freeFraction, 1)))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.13), .clear],
                        center: .center,
                        startRadius: 6,
                        endRadius: 58
                    )
                )

            Circle()
                .stroke(.white.opacity(0.055), lineWidth: 8)
                .padding(5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.32), tint, tint],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(5)
                .shadow(color: tint.opacity(0.38), radius: 7)
                .animation(.spring(response: 0.7, dampingFraction: 0.82), value: progress)

            Circle()
                .stroke(
                    tint.opacity(0.20),
                    style: StrokeStyle(lineWidth: 0.6, dash: [2, 6])
                )
                .padding(17)
                .rotationEffect(.degrees(orbit ? 360 : 0))

            Circle()
                .fill(tint)
                .frame(width: 3, height: 3)
                .offset(y: -46)
                .rotationEffect(.degrees(orbit ? 360 : 0))
                .opacity(0.78)
                .shadow(color: tint.opacity(0.8), radius: 3)

            VStack(spacing: 1) {
                Text(freeLabel)
                    .scaledFont(size: 20, weight: .bold, design: .rounded)
                    .tracking(-0.6)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text(title)
                    .scaledFont(size: 8, weight: .semibold)
                    .foregroundStyle(AppTheme.textSecondary)

                Text(detail)
                    .scaledFont(size: 7, weight: .medium)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 20)
        }
        .frame(width: 112, height: 112)
        .onAppear {
            withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) {
                orbit = true
            }
        }
    }
}
