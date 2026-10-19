import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            AuroraBackground()

            content

            WindowConfigurator()
                .frame(width: 0, height: 0)

            MenuBarBridge()
                .frame(width: 0, height: 0)
        }
        .frame(minWidth: 1_060, minHeight: 720)
        .preferredColorScheme(.dark)
        .environment(\.appFontScale, CGFloat(model.fontScale))
        .animation(.smooth(duration: 0.4), value: model.phase)
        .overlay(alignment: .topTrailing) {
            if let toast = model.toast {
                ToastBanner(toast: toast) {
                    model.dismissToast(toast)
                }
                .padding(.top, 52)
                .padding(.trailing, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: model.toast?.id)
        .task {
            model.notifications.activate()
            await model.notifications.refreshAuthorizationStatus()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .checking:
            BootView()
                .transition(.opacity)
        case .loggedOut:
            AuthView()
                .transition(.opacity.combined(with: .scale(scale: 0.99)))
        case .signedIn:
            mainShell
                .transition(.opacity.combined(with: .scale(scale: 0.995)))
        }
    }

    private var mainShell: some View {
        HStack(spacing: 14) {
            SidebarView()

            Group {
                switch model.selectedSection {
                case .dashboard:
                    DashboardView()
                case .instances:
                    InstancesView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.top, 46)
        .padding(.bottom, 16)
        .animation(.smooth(duration: 0.28), value: model.selectedSection)
    }
}

private struct BootView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(AppTheme.mint.opacity(0.12), lineWidth: 1)
                    .frame(width: 106, height: 106)
                    .scaleEffect(pulse ? 1.12 : 0.94)
                    .opacity(pulse ? 0.2 : 0.7)

                Circle()
                    .stroke(
                        AppTheme.aqua.opacity(0.24),
                        style: StrokeStyle(lineWidth: 0.7, dash: [2, 6])
                    )
                    .frame(width: 82, height: 82)
                    .rotationEffect(.degrees(pulse ? 120 : 0))

                BrandMark(size: 56)
            }

            VStack(spacing: 5) {
                Text("胡闹 AutoDL")
                    .scaledFont(size: 18, weight: .bold, design: .rounded)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("正在唤醒 GPU 哨兵…")
                    .scaledFont(size: 11, weight: .medium)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct ToastBanner: View {
    let toast: ToastMessage
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(toast.kind.tint.opacity(0.13))
                    .frame(width: 34, height: 34)
                Image(systemName: toast.kind.symbol)
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(toast.kind.tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(toast.title)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(toast.message)
                    .scaledFont(size: 10)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .scaledFont(size: 8, weight: .bold)
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 20, height: 20)
                    .background(.white.opacity(0.045), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .frame(width: 348, alignment: .leading)
        .glassPanel(cornerRadius: 19, tint: toast.kind.tint)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(toast.kind.tint.opacity(0.14))
                .frame(width: 90, height: 90)
                .blur(radius: 30)
                .offset(x: 30, y: -36)
                .allowsHitTesting(false)
        }
    }
}
