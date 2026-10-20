import AppKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updater: UpdateService
    @ObservedObject private var notifications = NotificationService.shared

    @State private var showLogoutConfirmation = false

    private let intervalChoices: [TimeInterval] = [10, 15, 30, 60]
    private let balanceThresholdChoices: [Double] = [10, 20, 50, 100]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                header
                updateCard

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        accountCard
                        appearanceCard
                        notificationCard
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 16) {
                        balanceCard
                        automationCard
                        aboutCard
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 26)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.top)
        .alert("退出并切换账号？", isPresented: $showLogoutConfirmation) {
            Button("退出登录", role: .destructive) {
                model.logout()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本地保存的 Token 会被移除，自动开机监控也会停止。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            EyebrowLabel(text: "Preferences", tint: AppTheme.amber)
            HStack(spacing: 10) {
                Text("设置")
                    .scaledFont(size: 27, weight: .bold, design: .rounded)
                    .foregroundStyle(AppTheme.textPrimary)
                    .tracking(-0.6)
                StatusPill(label: "本地运行", tint: AppTheme.mint)
            }
            Text("调整检查节奏、通知方式、应用更新与账户连接。")
                .scaledFont(size: 11.5)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var updateCard: some View {
        SettingsCard(
            eyebrow: "Updates",
            title: "版本更新",
            symbol: updateSymbol,
            tint: updateTint
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(updateHeadline)
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(updateSubtitle)
                            .scaledFont(size: 9.5)
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        StatusPill(
                            label: "当前 v\(updater.currentVersion)",
                            tint: AppTheme.aqua,
                            showsDot: false
                        )
                        updateActions
                    }
                }

                if showsReleaseNotes, let release = updater.release {
                    releaseNotes(release)
                }

                if showsProgressBlock {
                    progressBlock
                }

                if showsStarBanner {
                    updateStarBanner
                }
            }
            .animation(.smooth(duration: 0.25), value: updater.phase)
        }
    }

    private func releaseNotes(_ release: AppRelease) -> some View {
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("v\(release.version) 更新内容")
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(AppTheme.textSecondary)

                Text(release.assetName)
                    .scaledFont(size: 8, design: .monospaced)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)

                Spacer()

                Link(destination: release.pageURL) {
                    HStack(spacing: 3) {
                        Text("发布页")
                        Image(systemName: "arrow.up.right")
                            .scaledFont(size: 7, weight: .bold)
                    }
                    .scaledFont(size: 9, weight: .semibold)
                    .foregroundStyle(AppTheme.aqua.opacity(0.88))
                }
            }

            Text(notes.isEmpty ? "本次更新暂无详细说明。" : notes)
                .scaledFont(size: 9.5)
                .foregroundStyle(AppTheme.textSecondary.opacity(0.88))
                .lineSpacing(2.5)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.055), lineWidth: 0.6)
        }
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(progressCaption)
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer()

                Text(progressPercentLabel)
                    .scaledFont(size: 10, weight: .bold, design: .rounded)
                    .foregroundStyle(updateTint)
                    .monospacedDigit()
            }

            UpdateProgressBar(progress: progressValue, tint: updateTint)

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .scaledFont(size: 8, weight: .semibold)
                Text(progressFootnote)
                    .lineLimit(1)

                Spacer()

                if let lastCheckedAt = updater.lastCheckedAt {
                    Text("检查于 \(AppFormat.relative(lastCheckedAt))")
                }
            }
            .scaledFont(size: 8.5, weight: .medium)
            .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(12)
        .background(updateTint.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(updateTint.opacity(0.14), lineWidth: 0.6)
        }
    }

    private var updateStarBanner: some View {
        Button(action: AppLinks.openRepository) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(AppTheme.amber.opacity(0.13))
                        .frame(width: 30, height: 30)
                    Image(systemName: "star.fill")
                        .scaledFont(size: 11, weight: .semibold)
                        .foregroundStyle(AppTheme.amber)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(starHeadline)
                        .scaledFont(size: 10.5, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("开源免费 · 每颗 Star 都是作者 \(AppLinks.author) 持续更新的动力")
                        .scaledFont(size: 8.5)
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Text("去点 Star")
                    Image(systemName: "arrow.up.right")
                        .scaledFont(size: 7.5, weight: .bold)
                }
                .scaledFont(size: 9.5, weight: .bold)
                .foregroundStyle(AppTheme.amber)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                LinearGradient(
                    colors: [AppTheme.amber.opacity(0.085), AppTheme.amber.opacity(0.025)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppTheme.amber.opacity(0.16), lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
        .help("去 GitHub 给胡闹AutoDL 点个 Star")
    }

    @ViewBuilder
    private var updateActions: some View {
        switch updater.phase {
        case .checking:
            progressLabel("检查中…")
        case .idle, .upToDate:
            Button {
                Task { await updater.check() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .scaledFont(size: 9, weight: .semibold)
                    Text("检查更新")
                }
            }
            .buttonStyle(ActionButtonStyle(tint: AppTheme.aqua))
        case .available:
            Button {
                updater.download()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill")
                        .scaledFont(size: 9, weight: .semibold)
                    Text("下载更新")
                }
            }
            .buttonStyle(ActionButtonStyle(tint: AppTheme.mint, prominent: true))
        case .downloading:
            Button {
                updater.cancelDownload()
            } label: {
                Text("取消下载")
            }
            .buttonStyle(ActionButtonStyle(tint: AppTheme.rose))
        case .preparing:
            progressLabel("校验中…")
        case .readyToInstall:
            Button {
                updater.install()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .scaledFont(size: 9, weight: .semibold)
                    Text("重启并安装")
                }
            }
            .buttonStyle(ActionButtonStyle(tint: AppTheme.mint, prominent: true))
        case .installing:
            progressLabel("即将重启…")
        case .failed:
            Button {
                updater.retry()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .scaledFont(size: 9, weight: .semibold)
                    Text("重试")
                }
            }
            .buttonStyle(ActionButtonStyle(tint: AppTheme.amber, prominent: true))
        }
    }

    private func progressLabel(_ text: String) -> some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.75)
            Text(text)
        }
        .scaledFont(size: 10, weight: .medium)
        .foregroundStyle(AppTheme.textSecondary)
    }

    private var updateSymbol: String {
        switch updater.phase {
        case .failed: return "exclamationmark.triangle.fill"
        case .available, .readyToInstall: return "arrow.down.circle.fill"
        case .downloading, .preparing, .installing: return "arrow.triangle.2.circlepath.circle.fill"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    private var updateTint: Color {
        switch updater.phase {
        case .failed: return AppTheme.rose
        case .available, .readyToInstall: return AppTheme.mint
        case .downloading, .preparing, .installing, .checking: return AppTheme.aqua
        default: return AppTheme.violet
        }
    }

    private var updateHeadline: String {
        switch updater.phase {
        case .idle:
            return "更新检测已就绪"
        case .checking:
            return "正在检查新版本…"
        case .upToDate:
            return "已是最新版本"
        case .available:
            return "发现新版本 v\(updater.release?.version ?? "")"
        case .downloading:
            return "正在下载 v\(updater.release?.version ?? "")"
        case .preparing:
            return "正在校验安装包…"
        case .readyToInstall:
            return "更新已就绪，等待重启"
        case .installing:
            return "正在安装更新…"
        case .failed(let message):
            return "更新未完成 · \(message)"
        }
    }

    private var updateSubtitle: String {
        switch updater.phase {
        case .idle:
            return "每 24 小时自动检查一次，也可以随时手动检查。"
        case .checking:
            return "正在连接 GitHub Releases 获取最新版本信息。"
        case .upToDate:
            if let last = updater.lastCheckedAt {
                return "当前 v\(updater.currentVersion) 已是最新版本 · 检查于 \(AppFormat.relative(last))。"
            }
            return "当前 v\(updater.currentVersion) 已是最新版本。"
        case .available:
            return "下载、校验和安装都在应用内完成，无需打开 GitHub。"
        case .downloading:
            return "下载完成后会校验 SHA-256 与代码签名，再提示你重启安装。"
        case .preparing:
            return "正在核对安装包摘要、版本号和代码签名。"
        case .readyToInstall:
            return "安装包已通过校验，重启后会替换旧版本并自动重新打开。"
        case .installing:
            return "胡闹AutoDL 即将退出，更新完成后会自动重新启动。"
        case .failed:
            return "可以重试，或前往 GitHub 发布页手动下载安装包。"
        }
    }

    private var showsReleaseNotes: Bool {
        guard updater.release != nil else { return false }
        switch updater.phase {
        case .available, .downloading, .preparing, .readyToInstall, .installing, .failed:
            return true
        default:
            return false
        }
    }

    private var showsProgressBlock: Bool {
        switch updater.phase {
        case .downloading, .preparing, .readyToInstall, .installing:
            return true
        default:
            return false
        }
    }

    private var showsStarBanner: Bool {
        guard updater.release != nil else { return false }
        switch updater.phase {
        case .available, .downloading, .preparing, .readyToInstall, .installing, .failed:
            return true
        default:
            return false
        }
    }

    private var progressCaption: String {
        switch updater.phase {
        case .downloading: return "下载进度"
        case .preparing: return "安全校验"
        case .readyToInstall: return "安装包已就绪"
        case .installing: return "正在替换应用"
        default: return ""
        }
    }

    private var progressPercentLabel: String {
        switch updater.phase {
        case .downloading:
            return "\(Int((updater.progress * 100).rounded()))%"
        case .preparing:
            return "校验中"
        case .readyToInstall:
            return "100%"
        case .installing:
            return "即将重启"
        default:
            return ""
        }
    }

    private var progressValue: Double? {
        switch updater.phase {
        case .downloading: return updater.progress
        case .preparing, .installing: return nil
        case .readyToInstall: return 1
        default: return nil
        }
    }

    private var progressFootnote: String {
        switch updater.phase {
        case .downloading:
            return "\(bytesText(updater.receivedBytes)) / \(bytesText(updater.totalBytes)) · 安装包仅保存到本机"
        case .preparing:
            return "校验 SHA-256、版本号与代码签名"
        case .readyToInstall:
            return "签名有效 · 重启后替换当前应用"
        case .installing:
            return "应用退出后由本机脚本完成替换"
        default:
            return ""
        }
    }

    private var starHeadline: String {
        switch updater.phase {
        case .available:
            return "发现新版本，顺手给胡闹AutoDL 点个 Star 吧"
        case .downloading:
            return "更新下载中，点个 Star 支持作者"
        case .preparing:
            return "正在校验更新，点个 Star 支持作者"
        case .readyToInstall:
            return "更新已就绪，点个 Star 再重启"
        case .installing:
            return "正在安装更新，感谢你的 Star"
        case .failed:
            return "更新遇到问题，也可以去 GitHub 看看"
        default:
            return "喜欢胡闹AutoDL？去 GitHub 点个 Star 吧"
        }
    }

    private func bytesText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    private var accountCard: some View {
        SettingsCard(
            eyebrow: "Account",
            title: "账户与凭证",
            symbol: "person.crop.circle.badge.checkmark",
            tint: AppTheme.aqua
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 11) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.aqua.opacity(0.24), AppTheme.violet.opacity(0.18)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                        Text("A")
                            .scaledFont(size: 16, weight: .bold, design: .rounded)
                            .foregroundStyle(AppTheme.textPrimary.opacity(0.9))
                    }
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.7)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("AutoDL 账户")
                            .scaledFont(size: 12.5, weight: .semibold)
                            .foregroundStyle(AppTheme.textPrimary)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(AppTheme.mint)
                                .frame(width: 4, height: 4)
                            Text("Token 已安全连接")
                                .scaledFont(size: 9.5)
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }

                    Spacer()

                    StatusPill(label: "已登录", tint: AppTheme.mint)
                }

                SettingRow(label: "登录凭证", value: model.tokenHint, mono: true)
                SettingRow(label: "存储位置", value: "本机 · 仅当前用户可读")

                Button {
                    showLogoutConfirmation = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .scaledFont(size: 9, weight: .semibold)
                        Text("退出并切换账号")
                    }
                }
                .buttonStyle(ActionButtonStyle(tint: AppTheme.rose))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var appearanceCard: some View {
        SettingsCard(
            eyebrow: "Appearance",
            title: "界面字号",
            symbol: "textformat.size",
            tint: AppTheme.violet
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("全局字号")
                            .scaledFont(size: 11.5, weight: .semibold)
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("整个界面的文字会按比例缩放")
                            .scaledFont(size: 9.5)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    Spacer()
                    Text("\(Int((model.fontScale * 100).rounded()))%")
                        .scaledFont(size: 11, weight: .bold, design: .rounded)
                        .foregroundStyle(AppTheme.aqua)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { model.fontScale },
                        set: { model.setFontScale($0) }
                    ),
                    in: 0.85...1.3,
                    step: 0.05
                )
                .tint(AppTheme.aqua)
                .focusable(false)

                HStack {
                    Text("小 · 85%")
                    Spacer()
                    Text("标准 · 100%")
                    Spacer()
                    Text("特大 · 130%")
                }
                .scaledFont(size: 8, weight: .medium)
                .foregroundStyle(AppTheme.textTertiary)

                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.mint.opacity(0.10))
                            .frame(width: 29, height: 29)
                        Image(systemName: "textformat")
                            .scaledFont(size: 11, weight: .semibold)
                            .foregroundStyle(AppTheme.mint)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("发现空闲显卡")
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("字号预览 · 余额 \(model.balanceLabel)")
                            .scaledFont(size: 9.5)
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    Spacer(minLength: 6)

                    Button("恢复标准") {
                        model.setFontScale(1.0)
                    }
                    .buttonStyle(ActionButtonStyle(tint: .white))
                    .disabled(model.fontScale == 1.0)
                    .opacity(model.fontScale == 1.0 ? 0.45 : 1)
                }
                .padding(12)
                .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.055), lineWidth: 0.6)
                }
            }
        }
    }

    private var balanceCard: some View {
        SettingsCard(
            eyebrow: "Wallet",
            title: "账户余额",
            symbol: model.isLowBalance ? "exclamationmark.circle.fill" : "yensign.circle.fill",
            tint: model.isLowBalance ? AppTheme.amber : AppTheme.mint
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(model.balanceLabel)
                        .scaledFont(size: 28, weight: .bold, design: .rounded)
                        .foregroundStyle(
                            model.isLowBalance
                                ? AnyShapeStyle(AppTheme.amber)
                                : AnyShapeStyle(AppTheme.accentGradient)
                        )
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text("可用资金")
                        .scaledFont(size: 9.5, weight: .medium)
                        .foregroundStyle(AppTheme.textTertiary)

                    Spacer()

                    StatusPill(
                        label: model.isLowBalance ? "余额偏低" : "余额充足",
                        tint: model.isLowBalance ? AppTheme.amber : AppTheme.mint
                    )
                }

                VStack(spacing: 9) {
                    SettingRow(label: "现金余额", value: model.balance?.formattedCash ?? "—", mono: true)
                    SettingRow(label: "代金券", value: model.balance?.formattedVoucher ?? "—", mono: true)
                    SettingRow(label: "冻结余额", value: model.balance?.formattedBlocked ?? "—", mono: true)
                }
                .padding(12)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.05), lineWidth: 0.6)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("余额不足提醒阈值")
                            .scaledFont(size: 10, weight: .medium)
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Text(AccountBalance.currency(model.lowBalanceThreshold))
                            .scaledFont(size: 10, weight: .bold, design: .rounded)
                            .foregroundStyle(AppTheme.amber)
                            .monospacedDigit()
                    }

                    HStack(spacing: 6) {
                        ForEach(balanceThresholdChoices, id: \.self) { value in
                            let selected = abs(model.lowBalanceThreshold - value) < 0.001
                            Button {
                                model.setLowBalanceThreshold(value)
                            } label: {
                                Text(AccountBalance.currency(value))
                                    .scaledFont(size: 9.5, weight: .semibold)
                                    .foregroundStyle(
                                        selected ? Color.black.opacity(0.80) : AppTheme.textSecondary
                                    )
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 28)
                                    .background {
                                        if selected {
                                            Capsule().fill(
                                                LinearGradient(
                                                    colors: [AppTheme.amber, AppTheme.amber.opacity(0.72)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                        } else {
                                            Capsule().fill(.white.opacity(0.045))
                                        }
                                    }
                                    .overlay {
                                        if !selected {
                                            Capsule().strokeBorder(.white.opacity(0.06), lineWidth: 0.6)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let error = model.balanceError {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.exclamationmark")
                            .scaledFont(size: 9, weight: .semibold)
                        Text("余额同步失败：\(error)")
                            .lineLimit(2)
                    }
                    .scaledFont(size: 9.5, weight: .medium)
                    .foregroundStyle(AppTheme.rose)
                }

                HStack(spacing: 8) {
                    Button {
                        model.refreshNow()
                    } label: {
                        HStack(spacing: 5) {
                            if model.isRefreshing {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.75)
                            }
                            Text(model.isRefreshing ? "同步中…" : "刷新余额")
                        }
                    }
                    .buttonStyle(ActionButtonStyle(tint: .white))
                    .disabled(model.isRefreshing)

                    Spacer()

                    Text("更新于 \(AppFormat.relative(model.balance?.fetchedAt))")
                        .scaledFont(size: 8.5, weight: .medium)
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Text("余额低于阈值时提醒一次；余额恢复后，下一次低于阈值会重新提醒。")
                    .scaledFont(size: 9)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var notificationCard: some View {
        SettingsCard(
            eyebrow: "Notifications",
            title: "通知权限",
            symbol: notificationSymbol,
            tint: notifications.authorizationStatus == .denied ? AppTheme.rose : AppTheme.amber
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("空闲卡与自动开机提醒")
                        .scaledFont(size: 11.5, weight: .medium)
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    StatusPill(label: notificationLabel, tint: notificationTint)
                }

                Text("关闭自动开机时，目标主机一旦出现空闲卡就会提醒；自动开机成功和余额不足时也会通知。请保持胡闹AutoDL 在运行。")
                    .scaledFont(size: 10)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        handleNotificationAction()
                    } label: {
                        Text(notificationActionLabel)
                    }
                    .buttonStyle(ActionButtonStyle(tint: notificationTint, prominent: true))

                    Button {
                        model.sendTestNotification()
                    } label: {
                        Text("发送测试")
                    }
                    .buttonStyle(ActionButtonStyle(tint: .white))
                    .disabled(notifications.authorizationStatus == .denied)
                    .opacity(notifications.authorizationStatus == .denied ? 0.45 : 1)
                }
            }
        }
    }

    private var automationCard: some View {
        SettingsCard(
            eyebrow: "Automation",
            title: "监控与自动开机",
            symbol: "bolt.badge.clock.fill",
            tint: AppTheme.mint
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("自动开机")
                            .scaledFont(size: 11.5, weight: .semibold)
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(model.autoStartSubtitle)
                            .scaledFont(size: 9.5)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    Spacer()
                    CustomSwitch(isOn: model.autoStartEnabled) {
                        model.setAutoStart(!model.autoStartEnabled)
                    }
                }

                Rectangle()
                    .fill(.white.opacity(0.06))
                    .frame(height: 0.6)

                VStack(alignment: .leading, spacing: 9) {
                    Text("检查频率")
                        .scaledFont(size: 10, weight: .medium)
                        .foregroundStyle(AppTheme.textSecondary)

                    HStack(spacing: 6) {
                        ForEach(intervalChoices, id: \.self) { seconds in
                            Button {
                                model.setPollInterval(seconds)
                            } label: {
                                Text("\(Int(seconds)) 秒")
                                    .scaledFont(size: 10, weight: .semibold)
                                    .foregroundStyle(
                                        model.pollInterval == seconds
                                            ? Color.black.opacity(0.8)
                                            : AppTheme.textSecondary
                                    )
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 30)
                                    .background {
                                        if model.pollInterval == seconds {
                                            Capsule().fill(AppTheme.accentGradient)
                                        } else {
                                            Capsule().fill(.white.opacity(0.045))
                                        }
                                    }
                                    .overlay {
                                        if model.pollInterval != seconds {
                                            Capsule().strokeBorder(.white.opacity(0.06), lineWidth: 0.6)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("抢占依赖轮询，建议 10–15 秒。过于频繁可能触发 AutoDL 接口限流。")
                    .scaledFont(size: 9.5)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var aboutCard: some View {
        SettingsCard(
            eyebrow: "About",
            title: "关于胡闹AutoDL",
            symbol: "info.circle.fill",
            tint: AppTheme.violet
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 11) {
                    BrandMark(size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("胡闹")
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("AutoDL")
                                .foregroundStyle(AppTheme.mint)
                        }
                        .scaledFont(size: 15, weight: .bold, design: .rounded)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1") · macOS 15+")
                            .scaledFont(size: 9)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Button(action: AppLinks.openRepository) {
                        HStack(spacing: 7) {
                            Image(systemName: "star.fill")
                                .scaledFont(size: 9, weight: .bold)
                            Text("去 GitHub 给胡闹AutoDL 点个 Star")
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .scaledFont(size: 8, weight: .bold)
                                .opacity(0.65)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActionButtonStyle(tint: AppTheme.amber, prominent: true))

                    HStack(spacing: 4) {
                        Text("作者 \(AppLinks.author)")
                        Text("·")
                        Link(AppLinks.repositoryLabel, destination: AppLinks.repositoryURL)
                            .foregroundStyle(AppTheme.aqua.opacity(0.88))
                    }
                    .scaledFont(size: 9)
                    .foregroundStyle(AppTheme.textTertiary)
                }

                SettingRow(label: "数据存储", value: "仅本机")
                SettingRow(label: "第三方中转", value: "无")
                SettingRow(label: "接口来源", value: "AutoDL Web API")

                Text("第三方本地监控工具，与 AutoDL 官方无隶属关系。请遵守 AutoDL 服务条款。")
                    .scaledFont(size: 9)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        case .authorized: return "已开启"
        case .provisional: return "临时开启"
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

    private var notificationActionLabel: String {
        switch notifications.authorizationStatus {
        case .denied: return "打开系统设置"
        case .notDetermined: return "允许通知"
        default: return "打开通知设置"
        }
    }

    private func handleNotificationAction() {
        switch notifications.authorizationStatus {
        case .notDetermined:
            model.requestNotifications()
        default:
            model.openNotificationSettings()
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let eyebrow: String
    let title: String
    let symbol: String
    let tint: Color
    let content: Content

    init(
        eyebrow: String,
        title: String,
        symbol: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(tint.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    EyebrowLabel(text: eyebrow, tint: tint)
                    Text(title)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                }
                Spacer()
            }
            .padding(.bottom, 18)

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassPanel(cornerRadius: 24, tint: tint)
    }
}

private struct SettingRow: View {
    let label: String
    let value: String
    var mono = false

    var body: some View {
        HStack {
            Text(label)
                .scaledFont(size: 10, weight: .medium)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .scaledFont(size: 9.5, weight: .semibold, design: mono ? .monospaced : .default)
                .foregroundStyle(AppTheme.textPrimary.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct UpdateProgressBar: View {
    let progress: Double?
    var tint: Color = AppTheme.aqua

    @State private var shimmer = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.06))

                if let progress {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint, AppTheme.aqua],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(
                                width * min(max(progress, 0), 1),
                                progress > 0 ? 6 : 0
                            )
                        )
                        .shadow(color: tint.opacity(0.45), radius: 6)
                } else {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, tint.opacity(0.85), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(width * 0.35, 40))
                        .offset(x: shimmer ? width : -width * 0.35)
                }
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
            }
        }
        .frame(height: 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
        .animation(.smooth(duration: 0.25), value: progress)
    }
}
