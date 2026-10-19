import SwiftUI

struct QuickPanelView: View {
    @EnvironmentObject private var model: AppModel

    let onOpenDashboard: () -> Void
    let onOpenConsole: () -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header

            if model.phase == .signedIn {
                statusSummary

                if model.runningCount == 0 {
                    standbyHint
                }

                targetSection
                automationSection
                quickActions
            } else if model.phase == .checking {
                checkingCard
            } else {
                disconnectedCard
            }

            footer
        }
        .padding(15)
        .frame(width: 360)
        .background {
            ZStack {
                VisualEffectView(material: .popover)
                LinearGradient(
                    colors: [
                        Color(red: 0.035, green: 0.085, blue: 0.095).opacity(0.90),
                        Color(red: 0.045, green: 0.045, blue: 0.095).opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 33)

            VStack(alignment: .leading, spacing: 2) {
                Text("胡闹AutoDL")
                    .scaledFont(size: 14.5, weight: .bold, design: .rounded)
                    .foregroundStyle(AppTheme.textPrimary)
                HStack(spacing: 5) {
                    Circle()
                        .fill(modeTint)
                        .frame(width: 5, height: 5)
                        .shadow(color: modeTint.opacity(0.8), radius: 3)
                    Text(modeLabel)
                        .scaledFont(size: 9, weight: .semibold)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(model.isRefreshing ? AppTheme.mint : AppTheme.textSecondary)
                    .frame(width: 27, height: 27)
                    .background(.white.opacity(0.055), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.phase != .signedIn || model.isRefreshing)
            .help("立即刷新")

            Button(action: onOpenDashboard) {
                Image(systemName: "macwindow")
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 27, height: 27)
                    .background(.white.opacity(0.055), in: Circle())
            }
            .buttonStyle(.plain)
            .help("打开监控台")
        }
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(model.runningCount)")
                    .scaledFont(size: 28, weight: .bold, design: .rounded)
                    .foregroundStyle(model.runningCount > 0 ? AppTheme.mint : AppTheme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("/ \(model.instances.count) 台运行中")
                    .scaledFont(size: 10.5, weight: .medium)
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: model.isLowBalance ? "exclamationmark.circle.fill" : "yensign.circle.fill")
                        .scaledFont(size: 9, weight: .bold)
                    Text(model.balanceLabel)
                        .scaledFont(size: 10, weight: .bold, design: .rounded)
                        .monospacedDigit()
                }
                .foregroundStyle(model.isLowBalance ? AppTheme.amber : AppTheme.mint.opacity(0.88))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (model.isLowBalance ? AppTheme.amber : AppTheme.mint).opacity(0.09),
                    in: Capsule()
                )
            }

            if let instance = model.selectedInstance {
                HStack(spacing: 6) {
                    Image(systemName: "scope")
                        .scaledFont(size: 8.5, weight: .semibold)
                        .foregroundStyle(AppTheme.aqua.opacity(0.8))
                    Text(instance.name)
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                    Text(instance.state.label)
                        .scaledFont(size: 8, weight: .bold)
                        .foregroundStyle(instance.state.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(instance.state.tint.opacity(0.10), in: Capsule())

                    Spacer(minLength: 4)

                    Text("内存 \(instance.memoryFreeLabel) · 存储 \(instance.storageFreeLabel)")
                        .scaledFont(size: 9.5, weight: .semibold)
                        .foregroundStyle(AppTheme.aqua.opacity(0.82))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .help("\(instance.memoryDetailLabel) · \(instance.storageDetailLabel)")

                if let fraction = instance.storageUsedFraction {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.075))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.aqua.opacity(0.72), AppTheme.mint.opacity(0.82)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geometry.size.width * fraction))
                        }
                    }
                    .frame(height: 3.5)
                }
            } else {
                Text("还没有可监控的实例，打开监控台刷新看看。")
                    .scaledFont(size: 9.5)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: 15, tint: AppTheme.aqua)
    }

    private var standbyHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .scaledFont(size: 10, weight: .semibold)
                .foregroundStyle(AppTheme.amber.opacity(0.85))
            Text("当前没有实例在运行。选好监控对象并开启自动开机，胡闹AutoDL 替你守卡。")
                .scaledFont(size: 9.5, weight: .medium)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(AppTheme.amber.opacity(0.065), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppTheme.amber.opacity(0.14), lineWidth: 0.6)
        }
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                EyebrowLabel(text: "Monitor Target", tint: AppTheme.aqua)
                Spacer()
                Text(model.selectedInstance == nil ? "尚未选择" : "点选切换")
                    .scaledFont(size: 8.5, weight: .medium)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            if model.instances.isEmpty {
                Text("实例加载后会出现在这里。")
                    .scaledFont(size: 9.5)
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.instances) { instance in
                            targetChip(instance)
                        }
                    }
                }
            }
        }
    }

    private func targetChip(_ instance: AutoDLInstance) -> some View {
        let isSelected = instance.id == model.selectedInstanceID

        return Button {
            model.selectInstance(instance.id)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(instance.state.tint)
                    .frame(width: 5, height: 5)
                Text(instance.name)
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark")
                        .scaledFont(size: 7, weight: .bold)
                        .foregroundStyle(AppTheme.mint)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                isSelected ? AppTheme.mint.opacity(0.12) : Color.white.opacity(0.045),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected ? AppTheme.mint.opacity(0.30) : .white.opacity(0.065),
                        lineWidth: 0.7
                    )
            }
        }
        .buttonStyle(.plain)
        .help("\(instance.gpuName) × \(instance.gpuCount) · 内存剩余 \(instance.memoryFreeLabel) · 存储剩余 \(instance.storageFreeLabel)")
    }

    private var automationSection: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        (model.autoStartEnabled ? AppTheme.mint : Color.white)
                            .opacity(model.autoStartEnabled ? 0.12 : 0.055)
                    )
                    .frame(width: 30, height: 30)
                Image(systemName: model.autoStartEnabled ? "flame.fill" : "power")
                    .scaledFont(size: 11, weight: .bold)
                    .foregroundStyle(model.autoStartEnabled ? AppTheme.mint : AppTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("自动开机（疯狂模式）")
                    .scaledFont(size: 11.5, weight: .semibold)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(model.autoStartEnabled ? "空闲显卡一出现就自动抢占" : "只提醒，不自动开机")
                    .scaledFont(size: 8.5)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            CustomSwitch(isOn: model.autoStartEnabled) {
                model.setAutoStart(!model.autoStartEnabled)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .glassPanel(cornerRadius: 14, tint: model.autoStartEnabled ? AppTheme.mint : .white, interactive: true)
    }

    private var quickActions: some View {
        HStack(spacing: 7) {
            if let instance = model.selectedInstance,
               instance.state.isPoweredOff,
               model.actionInstanceID != instance.id {
                quickButton(title: "立即开机", symbol: "play.fill", tint: AppTheme.mint, prominent: true) {
                    model.powerOn(instance: instance)
                }
            }

            quickButton(title: "刷新状态", symbol: "arrow.clockwise", tint: .white) {
                onRefresh()
            }

            quickButton(title: "AutoDL 控制台", symbol: "arrow.up.right", tint: .white) {
                onOpenConsole()
            }
        }
    }

    private func quickButton(
        title: String,
        symbol: String,
        tint: Color,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if model.isRefreshing && symbol == "arrow.clockwise" {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.65)
                } else {
                    Image(systemName: symbol)
                        .scaledFont(size: 8, weight: .bold)
                }
                Text(title)
                    .scaledFont(size: 9.5, weight: .semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(prominent ? Color.black.opacity(0.82) : AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                prominent ? tint.opacity(0.88) : Color.white.opacity(0.045),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        prominent ? .white.opacity(0.35) : .white.opacity(0.07),
                        lineWidth: 0.7
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isRefreshing && symbol == "arrow.clockwise")
    }

    private var checkingCard: some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)
                .tint(AppTheme.aqua)
            Text("正在连接 AutoDL…")
                .scaledFont(size: 11, weight: .medium)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
        }
        .padding(13)
        .glassPanel(cornerRadius: 15, tint: AppTheme.aqua)
    }

    private var disconnectedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没有连接 AutoDL")
                .scaledFont(size: 12.5, weight: .semibold)
                .foregroundStyle(AppTheme.textPrimary)
            Text("打开主窗口完成登录，就能在这里快速选择目标、开关自动开机。")
                .scaledFont(size: 9.5)
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onOpenDashboard) {
                Text("打开登录窗口")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ActionButtonStyle(tint: AppTheme.mint, prominent: true))
        }
        .padding(13)
        .glassPanel(cornerRadius: 15, tint: AppTheme.mint)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onOpenDashboard) {
                HStack(spacing: 4) {
                    Text("打开监控台")
                    Image(systemName: "arrow.up.right")
                        .scaledFont(size: 7.5, weight: .bold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ActionButtonStyle(tint: AppTheme.aqua))

            Button(action: AppLinks.openRepository) {
                Image(systemName: "star.fill")
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(AppTheme.amber.opacity(0.85))
                    .frame(width: 32, height: 30)
                    .background(AppTheme.amber.opacity(0.07), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("作者 \(AppLinks.author) · GitHub 点个 Star")

            Button(action: onQuit) {
                Image(systemName: "power")
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 32, height: 30)
                    .background(.white.opacity(0.045), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("退出胡闹AutoDL")

            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .scaledFont(size: 8, weight: .medium)
                .foregroundStyle(AppTheme.textTertiary.opacity(0.8))
                .fixedSize()
        }
    }

    private var modeLabel: String {
        guard model.phase == .signedIn else {
            return model.phase == .checking ? "正在连接" : "等待登录"
        }
        if model.autoStartEnabled {
            return "疯狂模式 · 守候空闲显卡"
        }
        if model.runningCount > 0 {
            return "运行中 · \(model.runningCount)/\(model.instances.count) 台"
        }
        return "监控中 · 每 \(Int(model.pollInterval)) 秒检查"
    }

    private var modeTint: Color {
        guard model.phase == .signedIn else { return AppTheme.textTertiary }
        if model.autoStartEnabled { return AppTheme.amber }
        if model.runningCount > 0 { return AppTheme.mint }
        return AppTheme.aqua
    }
}
