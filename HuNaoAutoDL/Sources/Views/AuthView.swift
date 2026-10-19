import AppKit
import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var model: AppModel

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var capturedToken: String?
    @State private var webViewID = UUID()
    @State private var showManualToken = false
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 32) {
            intro
                .frame(width: 410, alignment: .leading)

            loginPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.leading, 44)
        .padding(.trailing, 34)
        .padding(.top, 54)
        .padding(.bottom, 28)
        .frame(maxWidth: 1260, maxHeight: 900)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(.smooth(duration: 0.7)) { appeared = true }
        }
        .sheet(isPresented: $showManualToken) {
            ManualTokenSheet()
                .environmentObject(model)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                BrandMark(size: 46)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("胡闹")
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("AutoDL")
                        .foregroundStyle(AppTheme.mint)
                }
                .scaledFont(size: 21, weight: .bold, design: .rounded)
            }

            Spacer(minLength: 30)

            HStack(spacing: 8) {
                Circle()
                    .fill(AppTheme.mint)
                    .frame(width: 5, height: 5)
                    .shadow(color: AppTheme.mint.opacity(0.8), radius: 5)
                EyebrowLabel(text: "GPU Sentinel · Local First")
            }

            Text("把显卡，\n守在手里。")
                .scaledFont(size: 45, weight: .bold, design: .rounded)
                .tracking(-1.2)
                .lineSpacing(2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.78), AppTheme.mint.opacity(0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 15)

            Text("登录 AutoDL 后，胡闹AutoDL 会替你盯住实例状态与目标主机的空闲显卡。有卡就提醒，或者直接帮你开机抢下。")
                .scaledFont(size: 14, weight: .regular)
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 15)
                .padding(.trailing, 12)

            VStack(alignment: .leading, spacing: 14) {
                FeatureLine(
                    symbol: "key.fill",
                    title: "自动抓取登录态",
                    detail: "官网扫码或密码登录，成功后自动读取 Token"
                )
                FeatureLine(
                    symbol: "cpu.fill",
                    title: "锁定目标主机",
                    detail: "监控所选实例所在主机的空闲 GPU"
                )
                FeatureLine(
                    symbol: "bolt.badge.clock.fill",
                    title: "守候与提醒",
                    detail: "自动开机，或仅在有卡时弹出通知"
                )
            }
            .padding(.top, 26)

            Spacer(minLength: 24)

            HStack(spacing: 7) {
                Image(systemName: "lock.shield.fill")
                    .scaledFont(size: 10, weight: .semibold)
                Text("Token 仅保存在本机受保护文件，不经由第三方服务器")
                    .scaledFont(size: 10, weight: .medium)
            }
            .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var loginPanel: some View {
        VStack(spacing: 0) {
            browserHeader

            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(height: 0.7)

            if let error = model.loginError {
                loginErrorBanner(error)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ZStack {
                LoginWebView(
                    isLoading: $isLoading,
                    loadError: $loadError,
                    onTokenCaptured: handleCapturedToken
                )
                .id(webViewID)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.7)
                }

                if let loadError, !isLoading {
                    networkErrorOverlay(loadError)
                }

                if model.isLoggingIn {
                    verifyingOverlay
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(.white.opacity(0.05))
                .frame(height: 0.7)

            browserFooter
        }
        .glassPanel(cornerRadius: 30, tint: AppTheme.aqua)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .clear, AppTheme.aqua.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
        }
    }

    private var browserHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(AppTheme.rose.opacity(0.72)).frame(width: 7, height: 7)
                Circle().fill(AppTheme.amber.opacity(0.70)).frame(width: 7, height: 7)
                Circle().fill(AppTheme.mint.opacity(0.72)).frame(width: 7, height: 7)
            }
            .padding(.trailing, 3)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .scaledFont(size: 8.5, weight: .semibold)
                    .foregroundStyle(AppTheme.mint.opacity(0.82))
                Text("www.autodl.com/login")
                    .scaledFont(size: 10.5, weight: .medium, design: .monospaced)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.055), in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.07), lineWidth: 0.6)
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.68)
                    .frame(width: 20, height: 20)
            } else {
                HStack(spacing: 5) {
                    Circle()
                        .fill(AppTheme.mint)
                        .frame(width: 5, height: 5)
                    Text("登录页面")
                        .scaledFont(size: 10, weight: .medium)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }

            Button {
                reloadBrowser()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .help("重新加载登录页")
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }

    private var browserFooter: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppTheme.mint.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: "sparkle.magnifyingglass")
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(AppTheme.mint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("登录态自动捕获中")
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("完成登录后无需复制，胡闹AutoDL 会自动连接")
                    .scaledFont(size: 9.5)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            if let capturedToken, model.loginError != nil, !model.isLoggingIn {
                Button("重试连接") {
                    Task { await model.signIn(token: capturedToken) }
                }
                .buttonStyle(ActionButtonStyle(tint: AppTheme.mint, prominent: true))
            }

            Button("使用 Token") {
                showManualToken = true
            }
            .scaledFont(size: 10.5, weight: .semibold)
            .foregroundStyle(AppTheme.textSecondary)
            .buttonStyle(.plain)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.white.opacity(0.055), in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.6)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private func loginErrorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .scaledFont(size: 10, weight: .semibold)
            Text(error)
                .scaledFont(size: 10.5, weight: .medium)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button {
                model.loginError = nil
            } label: {
                Image(systemName: "xmark")
                    .scaledFont(size: 9, weight: .bold)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(AppTheme.rose)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(AppTheme.rose.opacity(0.09))
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.rose.opacity(0.14)).frame(height: 0.6)
        }
    }

    private func networkErrorOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .scaledFont(size: 25, weight: .light)
                .foregroundStyle(AppTheme.amber)
            Text("登录页加载失败")
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(AppTheme.textPrimary)
            Text(message)
                .scaledFont(size: 10.5)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button("重新加载") { reloadBrowser() }
                .buttonStyle(ActionButtonStyle(tint: AppTheme.mint, prominent: true))
        }
        .padding(26)
        .glassPanel(cornerRadius: 22, tint: AppTheme.amber)
    }

    private var verifyingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .tint(AppTheme.mint)
            Text("正在验证登录态…")
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .glassPanel(cornerRadius: 20, tint: AppTheme.mint)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func handleCapturedToken(_ token: String) {
        capturedToken = token
        guard !model.isLoggingIn else { return }
        Task { await model.signIn(token: token) }
    }

    private func reloadBrowser() {
        loadError = nil
        isLoading = true
        webViewID = UUID()
    }
}

private struct FeatureLine: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(AppTheme.mint.opacity(0.88))
                .frame(width: 30, height: 30)
                .background(AppTheme.mint.opacity(0.075), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(AppTheme.mint.opacity(0.16), lineWidth: 0.6)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(AppTheme.textPrimary.opacity(0.90))
                Text(detail)
                    .scaledFont(size: 10.5)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }
}

private struct ManualTokenSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.06, blue: 0.07)
            Circle()
                .fill(AppTheme.mint.opacity(0.14))
                .frame(width: 330, height: 330)
                .blur(radius: 100)
                .offset(x: -160, y: -130)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.mint.opacity(0.10))
                            .frame(width: 40, height: 40)
                        Image(systemName: "key.horizontal.fill")
                            .scaledFont(size: 15, weight: .semibold)
                            .foregroundStyle(AppTheme.mint)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("使用 Token 登录")
                            .scaledFont(size: 16, weight: .bold)
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("支持网页登录 Token 或 AutoDL 开发者 Token")
                            .scaledFont(size: 10.5)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .scaledFont(size: 10, weight: .bold)
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text("Token")
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.top, 22)
                    .padding(.bottom, 8)

                HStack(spacing: 8) {
                    SecureField("粘贴 AutoDL Token", text: $token)
                        .textFieldStyle(.plain)
                        .scaledFont(size: 12, design: .monospaced)
                        .foregroundStyle(AppTheme.textPrimary)
                        .onSubmit { submit() }

                    Button("粘贴") {
                        if let value = NSPasteboard.general.string(forType: .string) {
                            token = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .buttonStyle(.plain)
                    .scaledFont(size: 10.5, weight: .semibold)
                    .foregroundStyle(AppTheme.mint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.mint.opacity(0.09), in: Capsule())
                }
                .padding(.horizontal, 13)
                .frame(height: 42)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.7)
                }

                if let error = model.loginError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(error)
                    }
                    .scaledFont(size: 10.5, weight: .medium)
                    .foregroundStyle(AppTheme.rose)
                    .padding(.top, 10)
                }

                Text("Token 会保存到仅当前用户可读的本机文件，不会上传到任何第三方服务。")
                    .scaledFont(size: 9.5)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineSpacing(2)
                    .padding(.top, 12)

                Spacer(minLength: 18)

                HStack(spacing: 10) {
                    Button("取消") { dismiss() }
                        .buttonStyle(ActionButtonStyle(tint: .white))

                    Spacer()

                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 6) {
                            if model.isLoggingIn {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.black.opacity(0.8))
                            }
                            Text(model.isLoggingIn ? "连接中…" : "连接 AutoDL")
                        }
                        .frame(minWidth: 88)
                    }
                    .buttonStyle(ActionButtonStyle(tint: AppTheme.mint, prominent: true))
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoggingIn)
                    .opacity(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
            }
            .padding(24)
        }
        .frame(width: 510, height: 350)
        .onAppear {
            withAnimation(.smooth(duration: 0.35)) { appeared = true }
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.16))
                .frame(width: 34, height: 3)
                .padding(.top, 8)
        }
    }

    private func submit() {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !model.isLoggingIn else { return }
        Task {
            await model.signIn(token: value)
            if model.phase == .signedIn {
                dismiss()
            }
        }
    }
}
