import AppKit
import SwiftUI

struct InstancesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var instanceToStop: AutoDLInstance?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                header
                summaryStrip

                if model.instances.isEmpty {
                    emptyCard
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(model.instances) { instance in
                            InstanceRow(
                                instance: instance,
                                isTarget: instance.id == model.selectedInstanceID,
                                isActing: model.actionInstanceID == instance.id,
                                autoStartEnabled: model.autoStartEnabled,
                                onSelect: { model.selectInstance(instance.id) },
                                onPowerOn: { model.powerOn(instance: instance) },
                                onPowerOff: { instanceToStop = instance }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 26)
        }
        .scrollIndicators(.never)
        .alert(
            "关闭实例？",
            isPresented: Binding(
                get: { instanceToStop != nil },
                set: { if !$0 { instanceToStop = nil } }
            ),
            presenting: instanceToStop
        ) { instance in
            Button("关机", role: .destructive) {
                model.powerOff(instance: instance)
                instanceToStop = nil
            }
            Button("取消", role: .cancel) {
                instanceToStop = nil
            }
        } message: { instance in
            Text("确定要关闭「\(instance.name)」吗？如果自动开机已开启，胡闹会在检测到空闲显卡后重新开机。")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                EyebrowLabel(text: "Instance Fleet", tint: AppTheme.aqua)
                HStack(spacing: 10) {
                    Text("我的实例")
                        .scaledFont(size: 27, weight: .bold, design: .rounded)
                        .foregroundStyle(AppTheme.textPrimary)
                        .tracking(-0.6)
                    StatusPill(
                        label: "\(model.instances.count) 台",
                        tint: AppTheme.aqua
                    )
                }
                Text("查看所有实例状态，或切换胡闹的监控目标。")
                    .scaledFont(size: 11.5)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if model.isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(AppTheme.aqua)
                        Text("同步中")
                            .scaledFont(size: 9.5, weight: .medium)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .glassPanel(cornerRadius: 11, tint: .white)
                }
                GlassIconButton(
                    symbol: "arrow.clockwise",
                    action: { model.refreshNow() },
                    isActive: model.isRefreshing,
                    help: "刷新实例"
                )
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            FleetStat(
                label: "全部实例",
                value: "\(model.instances.count)",
                symbol: "square.stack.3d.up.fill",
                tint: AppTheme.aqua
            )
            divider
            FleetStat(
                label: "运行中",
                value: "\(model.runningCount)",
                symbol: "bolt.fill",
                tint: AppTheme.mint
            )
            divider
            FleetStat(
                label: "监控目标",
                value: model.selectedInstance.map { String($0.name.prefix(8)) } ?? "未选择",
                symbol: "scope",
                tint: AppTheme.violet
            )
            divider
            FleetStat(
                label: "自动开机",
                value: model.autoStartEnabled ? "已开启" : "已关闭",
                symbol: "power",
                tint: model.autoStartEnabled ? AppTheme.mint : AppTheme.textSecondary
            )
        }
        .padding(.horizontal, 6)
        .frame(height: 74)
        .glassPanel(cornerRadius: 20, tint: AppTheme.aqua)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(width: 0.6, height: 30)
    }

    private var emptyCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.aqua.opacity(0.08))
                    .frame(width: 78, height: 78)
                Image(systemName: "square.stack.3d.up.slash")
                    .scaledFont(size: 28, weight: .light)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Text("账号下还没有实例")
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(AppTheme.textPrimary)
            Text("去 AutoDL 创建一台 GPU 实例，然后回来刷新。胡闹只负责替你盯着它。")
                .scaledFont(size: 11.5)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                if let url = URL(string: "https://www.autodl.com/console/instance/list") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Text("打开 AutoDL 控制台")
                    Image(systemName: "arrow.up.right")
                        .scaledFont(size: 8, weight: .bold)
                }
            }
            .buttonStyle(ActionButtonStyle(tint: AppTheme.mint, prominent: true))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .glassPanel(cornerRadius: 26, tint: AppTheme.aqua)
    }
}

private struct FleetStat: View {
    let label: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .scaledFont(size: 11, weight: .semibold)
                .foregroundStyle(tint.opacity(0.82))
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .scaledFont(size: 9, weight: .medium)
                    .foregroundStyle(AppTheme.textTertiary)
                Text(value)
                    .scaledFont(size: 14, weight: .bold, design: .rounded)
                    .foregroundStyle(AppTheme.textPrimary.opacity(0.90))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }
}

private struct InstanceRow: View {
    let instance: AutoDLInstance
    let isTarget: Bool
    let isActing: Bool
    let autoStartEnabled: Bool
    let onSelect: () -> Void
    let onPowerOn: () -> Void
    let onPowerOff: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [instance.state.tint.opacity(0.18), instance.state.tint.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(instance.state.tint.opacity(0.18), lineWidth: 0.7)
                        }
                    Image(systemName: "memorychip.fill")
                        .scaledFont(size: 20, weight: .medium)
                        .foregroundStyle(instance.state.tint.opacity(0.88))
                }

                if isTarget {
                    Image(systemName: "scope")
                        .scaledFont(size: 8, weight: .bold)
                        .foregroundStyle(AppTheme.mint)
                        .padding(.top, 6)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(instance.name)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    StatusPill(label: instance.state.label, tint: instance.state.tint)

                    if isTarget {
                        StatusPill(label: "监控目标", tint: AppTheme.mint, showsDot: false)
                    }

                    if isTarget && autoStartEnabled {
                        Image(systemName: "power")
                            .scaledFont(size: 8, weight: .bold)
                            .foregroundStyle(AppTheme.mint.opacity(0.7))
                            .help("自动开机已开启")
                    }
                }

                HStack(spacing: 12) {
                    MetaItem(symbol: "cpu", text: "\(instance.gpuName) × \(instance.gpuCount)")
                    MetaItem(symbol: "mappin.and.ellipse", text: instance.displayRegion)
                    MetaItem(
                        symbol: "server.rack",
                        text: instance.machineID.isEmpty ? "主机待同步" : instance.machineID
                    )
                }

                HStack(spacing: 12) {
                    MetaItem(symbol: "creditcard", text: instance.chargeLabel)
                    MetaItem(symbol: "number", text: "实例 \(instance.shortID)")
                    if let startedAt = instance.startedAt, instance.state == .running {
                        MetaItem(symbol: "clock", text: "启动于 \(AppFormat.dateTime.string(from: startedAt))")
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }

            Spacer(minLength: 12)

            if !isTarget {
                Button(action: onSelect) {
                    Text("设为目标")
                }
                .buttonStyle(ActionButtonStyle(tint: AppTheme.aqua))
            }

            Button {
                if instance.state == .running {
                    onPowerOff()
                } else {
                    onPowerOn()
                }
            } label: {
                HStack(spacing: 6) {
                    if isActing {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: instance.state == .running ? "stop.fill" : "play.fill")
                            .scaledFont(size: 8, weight: .bold)
                    }
                    Text(instance.state == .running ? "关机" : (instance.state.isBusy ? instance.state.label : "开机"))
                }
                .frame(minWidth: 38)
            }
            .buttonStyle(
                ActionButtonStyle(
                    tint: instance.state == .running ? AppTheme.rose : AppTheme.mint,
                    prominent: instance.state != .running
                )
            )
            .disabled(isActing || instance.state.isBusy || instance.state == .unknown)
            .opacity((isActing || instance.state.isBusy || instance.state == .unknown) ? 0.5 : 1)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .background {
            if hovered || isTarget {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill((isTarget ? AppTheme.mint : Color.white).opacity(isTarget ? 0.035 : 0.018))
            }
        }
        .glassPanel(
            cornerRadius: 22,
            tint: isTarget ? AppTheme.mint : .white
        )
        .overlay {
            if isTarget {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(AppTheme.mint.opacity(0.25), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) { hovered = hovering }
        }
    }
}

private struct MetaItem: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .scaledFont(size: 8, weight: .semibold)
                .foregroundStyle(AppTheme.textTertiary)
            Text(text)
                .scaledFont(size: 9, weight: .medium)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
