import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updater: UpdateService
    @State private var starHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 22)

            divider

            EyebrowLabel(text: "Workspace", tint: AppTheme.textTertiary)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 9)

            VStack(spacing: 5) {
                ForEach(SidebarSection.allCases) { section in
                    SidebarItem(
                        section: section,
                        isSelected: model.selectedSection == section,
                        showsUpdateBadge: section == .settings && updater.showsUpdateAttention
                    ) {
                        withAnimation(.smooth(duration: 0.32)) {
                            model.selectedSection = section
                        }
                    }
                }

                starItem
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 24)

            liveStatusCard
                .padding(.horizontal, 12)

            accountCard
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .frame(width: 224)
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.black.opacity(0.10))
        }
        .glassPanel(cornerRadius: 26, tint: AppTheme.mint)
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(AppTheme.mint.opacity(0.12))
                .frame(width: 150, height: 150)
                .blur(radius: 60)
                .offset(x: -55, y: -65)
                .allowsHitTesting(false)
        }
    }

    private var brand: some View {
        HStack(spacing: 11) {
            BrandMark(size: 40)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("胡闹")
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("AutoDL")
                        .foregroundStyle(AppTheme.mint)
                }
                .scaledFont(size: 17, weight: .bold, design: .rounded)
                .lineLimit(1)

                Text("GPU SENTINEL")
                    .scaledFont(size: 7.5, weight: .bold, design: .rounded)
                    .tracking(1.5)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.10), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.7)
            .padding(.horizontal, 18)
    }

    private var liveStatusCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(AppTheme.mint.opacity(0.13))
                        .frame(width: 18, height: 18)
                    Circle()
                        .fill(AppTheme.mint)
                        .frame(width: 5, height: 5)
                        .shadow(color: AppTheme.mint.opacity(0.8), radius: 4)
                }
                Text("守候中")
                    .scaledFont(size: 10.5, weight: .semibold)
                    .foregroundStyle(AppTheme.mint.opacity(0.92))
                Spacer()
                Text("LIVE")
                    .scaledFont(size: 7.5, weight: .bold, design: .rounded)
                    .tracking(1)
                    .foregroundStyle(AppTheme.mint.opacity(0.72))
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(model.runningCount)")
                    .scaledFont(size: 24, weight: .bold, design: .rounded)
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()
                Text("/ \(model.instances.count) 台运行中")
                    .scaledFont(size: 9.5, weight: .medium)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .scaledFont(size: 8, weight: .semibold)
                Text("同步于 \(AppFormat.relative(model.lastUpdated))")
                    .scaledFont(size: 8.5, weight: .medium)
            }
            .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(13)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.white.opacity(0.065), lineWidth: 0.6)
        }
    }

    private var accountCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.aqua.opacity(0.22), AppTheme.violet.opacity(0.22)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 31, height: 31)
                Text("A")
                    .scaledFont(size: 12, weight: .bold, design: .rounded)
                    .foregroundStyle(AppTheme.textPrimary.opacity(0.88))
            }
            .overlay {
                Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.7)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("AutoDL 账户")
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(AppTheme.textPrimary.opacity(0.88))
                HStack(spacing: 4) {
                    Circle()
                        .fill(balanceTint)
                        .frame(width: 4, height: 4)
                    Text(model.balance == nil ? "余额同步中" : "余额 \(model.balanceLabel)")
                        .scaledFont(size: 8.5, weight: .medium)
                        .foregroundStyle(model.isLowBalance ? AppTheme.amber.opacity(0.88) : AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .help(balanceHelp)

            Spacer(minLength: 0)

            Button {
                model.selectedSection = .settings
            } label: {
                Image(systemName: "gearshape.fill")
                    .scaledFont(size: 10.5, weight: .semibold)
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 25, height: 25)
                    .background(.white.opacity(0.045), in: Circle())
            }
            .buttonStyle(.plain)
            .help("设置")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white.opacity(0.028), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.055), lineWidth: 0.6)
        }
    }

    private var starItem: some View {
        Button {
            AppLinks.openRepository()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "star.fill")
                    .scaledFont(size: 12.5, weight: .semibold)
                    .foregroundStyle(AppTheme.amber)
                    .frame(width: 22)

                Text("点个 Star")
                    .scaledFont(size: 12.5, weight: .medium)
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer()

                Text(AppLinks.author)
                    .scaledFont(size: 8.5, weight: .bold, design: .rounded)
                    .foregroundStyle(AppTheme.amber.opacity(0.78))
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .contentShape(Rectangle())
            .background(
                AppTheme.amber.opacity(starHovered ? 0.10 : 0.038),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppTheme.amber.opacity(0.10), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) { starHovered = hovering }
        }
        .help("作者 \(AppLinks.author) · \(AppLinks.repositoryLabel)")
    }

    private var balanceTint: Color {
        guard model.balance != nil else { return AppTheme.textTertiary }
        return model.isLowBalance ? AppTheme.amber : AppTheme.mint
    }

    private var balanceHelp: String {
        guard let balance = model.balance else { return "正在同步 AutoDL 账户余额" }
        return "现金 \(balance.formattedCash) · 代金券 \(balance.formattedVoucher) · 冻结 \(balance.formattedBlocked)"
    }
}

private struct SidebarItem: View {
    let section: SidebarSection
    let isSelected: Bool
    var showsUpdateBadge = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: section.symbol)
                    .scaledFont(size: 12.5, weight: .semibold)
                    .foregroundStyle(isSelected ? AppTheme.mint : AppTheme.textSecondary)
                    .frame(width: 22)

                Text(section.title)
                    .scaledFont(size: 12.5, weight: isSelected ? .semibold : .medium)
                    .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)

                Spacer()

                if showsUpdateBadge && !isSelected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(AppTheme.amber)
                            .frame(width: 4, height: 4)
                            .shadow(color: AppTheme.amber.opacity(0.9), radius: 4)
                        Text("NEW")
                            .scaledFont(size: 7, weight: .bold, design: .rounded)
                            .tracking(0.6)
                            .foregroundStyle(AppTheme.amber.opacity(0.9))
                    }
                }

                if isSelected {
                    Circle()
                        .fill(AppTheme.mint)
                        .frame(width: 4, height: 4)
                        .shadow(color: AppTheme.mint.opacity(0.9), radius: 5)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [AppTheme.mint.opacity(0.13), AppTheme.aqua.opacity(0.045)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            : AnyShapeStyle(.white.opacity(hovered ? 0.045 : 0.001))
                    )
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppTheme.mint.opacity(0.16), lineWidth: 0.7)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) { hovered = hovering }
        }
    }
}
