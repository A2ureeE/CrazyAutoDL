import SwiftUI

struct BillingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var rangeDays = 14
    @State private var hoveredDate: Date?

    private var snapshot: BillingSnapshot? { model.billing }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                header

                if let error = model.billingError, snapshot != nil {
                    warningBanner(error)
                }

                if let snapshot {
                    summaryRow(snapshot)

                    if snapshot.records.isEmpty {
                        emptyCard
                    } else {
                        chartCard(snapshot)

                        HStack(alignment: .top, spacing: 16) {
                            compositionCard(snapshot)
                                .frame(maxWidth: .infinity, minHeight: 368)

                            recentBillsCard(snapshot)
                                .frame(width: 392)
                                .frame(minHeight: 368)
                        }
                    }
                } else if let error = model.billingError {
                    errorCard(error)
                } else {
                    loadingCard
                }
            }
            .padding(.bottom, 26)
        }
        .scrollIndicators(.never)
        .task {
            model.refreshBilling()
        }
        .animation(.smooth(duration: 0.3), value: model.billing)
        .animation(.smooth(duration: 0.3), value: model.isBillingLoading)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                EyebrowLabel(text: "Billing Ledger", tint: AppTheme.amber)
                HStack(spacing: 10) {
                    Text("账单")
                        .scaledFont(size: 27, weight: .bold, design: .rounded)
                        .foregroundStyle(AppTheme.textPrimary)
                        .tracking(-0.6)
                    StatusPill(
                        label: snapshot == nil ? "同步中" : "近 \(rangeDays) 天",
                        tint: snapshot == nil ? AppTheme.textSecondary : AppTheme.amber
                    )
                }
                Text("每一度电、每一张卡，都算得明明白白。")
                    .scaledFont(size: 11.5)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if let fetchedAt = snapshot?.fetchedAt {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppTheme.amber)
                            .frame(width: 5, height: 5)
                        Text("同步于 \(AppFormat.relative(fetchedAt))")
                            .scaledFont(size: 9.5, weight: .medium)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .glassPanel(cornerRadius: 11, tint: .white)
                }

                Button {
                    AppLinks.openBillingConsole()
                } label: {
                    HStack(spacing: 5) {
                        Text("完整账单")
                        Image(systemName: "arrow.up.right")
                            .scaledFont(size: 8, weight: .bold)
                    }
                }
                .buttonStyle(ActionButtonStyle(tint: AppTheme.aqua))

                GlassIconButton(
                    symbol: "arrow.clockwise",
                    action: { model.refreshBilling(force: true) },
                    isActive: model.isBillingLoading,
                    help: "刷新账单"
                )
            }
        }
    }

    private func summaryRow(_ snapshot: BillingSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            spendSummary(snapshot)
                .frame(maxWidth: .infinity, minHeight: 178)

            balanceCard
                .frame(width: 288)
                .frame(minHeight: 178)
        }
    }

    private func spendSummary(_ snapshot: BillingSnapshot) -> some View {
        let total = snapshot.totalSpend(days: rangeDays)
        let dailyAverage = rangeDays > 0 ? total / Double(rangeDays) : 0
        let dayLeft = snapshot.estimatedDaysRemaining(balance: model.balance?.available)

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowLabel(text: "Spending Pulse", tint: AppTheme.mint)
                    Text("近 \(rangeDays) 天消费")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .scaledFont(size: 9, weight: .semibold)
                    Text("日均 \(currency(dailyAverage))")
                        .scaledFont(size: 9.5, weight: .medium)
                }
                .foregroundStyle(AppTheme.textTertiary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(currency(total))
                    .scaledFont(size: 37, weight: .bold, design: .rounded)
                    .tracking(-1.2)
                    .foregroundStyle(
                        total > 0
                            ? AnyShapeStyle(AppTheme.accentGradient)
                            : AnyShapeStyle(AppTheme.textPrimary.opacity(0.82))
                    )
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.5, dampingFraction: 0.82), value: total)

            }
            .padding(.top, 10)

            Spacer(minLength: 12)

            HStack(spacing: 0) {
                summaryStat(
                    label: "今日",
                    value: currency(snapshot.todaySpend),
                    tint: AppTheme.aqua
                )
                summaryDivider
                summaryStat(
                    label: "近 7 天",
                    value: currency(snapshot.last7Spend),
                    tint: AppTheme.mint
                )
                summaryDivider
                summaryStat(
                    label: "本月",
                    value: currency(snapshot.monthSpend),
                    tint: AppTheme.violet
                )
                summaryDivider
                summaryStat(
                    label: "余额可撑",
                    value: dayLeft.map { "\($0) 天" } ?? "—",
                    tint: dayLeft.map { $0 < 7 ? AppTheme.rose : AppTheme.amber } ?? AppTheme.textTertiary,
                    help: "按最近 7 天的日均消费估算"
                )
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 24, tint: AppTheme.mint)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(AppTheme.mint.opacity(0.10))
                .frame(width: 160, height: 160)
                .blur(radius: 55)
                .offset(x: 60, y: -70)
                .allowsHitTesting(false)
        }
    }

    private var balanceCard: some View {
        let balance = model.balance
        let cash = max(balance?.cash ?? 0, 0)
        let voucher = max(balance?.voucher ?? 0, 0)
        let blocked = max(balance?.blocked ?? 0, 0)
        let total = cash + voucher + blocked

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowLabel(text: "Wallet", tint: AppTheme.aqua)
                    Text("账户余额")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                }
                Spacer()
                Image(systemName: "wallet.bifold.fill")
                    .scaledFont(size: 14, weight: .medium)
                    .foregroundStyle(AppTheme.aqua.opacity(0.7))
            }

            Text(model.balanceLabel)
                .scaledFont(size: 31, weight: .bold, design: .rounded)
                .tracking(-0.8)
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
                .padding(.top, 12)

            Text(balance == nil ? "正在同步钱包" : "现金 + 代金券可用")
                .scaledFont(size: 9)
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.top, 2)

            Spacer(minLength: 12)

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    if total > 0 {
                        segment(width: geometry.size.width * CGFloat(cash / total), color: AppTheme.mint)
                        segment(width: geometry.size.width * CGFloat(voucher / total), color: AppTheme.aqua)
                        segment(width: geometry.size.width * CGFloat(blocked / total), color: AppTheme.amber.opacity(0.7))
                    } else {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.white.opacity(0.07))
                    }
                }
            }
            .frame(height: 7)
            .clipShape(Capsule())

            HStack(spacing: 10) {
                balanceLegend(label: "现金", value: balance?.formattedCash ?? "—", tint: AppTheme.mint)
                balanceLegend(label: "代金券", value: balance?.formattedVoucher ?? "—", tint: AppTheme.aqua)
                balanceLegend(label: "冻结", value: balance?.formattedBlocked ?? "—", tint: AppTheme.amber)
            }
            .padding(.top, 10)
        }
        .padding(18)
        .glassPanel(cornerRadius: 24, tint: AppTheme.aqua)
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: max(0, width))
    }

    private func balanceLegend(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(tint)
                    .frame(width: 4, height: 4)
                Text(label)
                    .scaledFont(size: 8, weight: .medium)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Text(value)
                .scaledFont(size: 9.5, weight: .semibold, design: .rounded)
                .foregroundStyle(AppTheme.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartCard(_ snapshot: BillingSnapshot) -> some View {
        let days = snapshot.dailySeries(days: rangeDays)
        let activeDay = days.first { $0.date == hoveredDate } ?? days.last
        let average = days.isEmpty ? 0 : days.reduce(0) { $0 + $1.amount } / Double(days.count)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowLabel(text: "Daily Burn", tint: AppTheme.aqua)
                    Text("每日消费")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Spacer()

                if let activeDay {
                    HStack(spacing: 5) {
                        Text(AppFormat.billDay.string(from: activeDay.date))
                            .scaledFont(size: 9, weight: .medium)
                            .foregroundStyle(AppTheme.textTertiary)
                        Text(currency(activeDay.amount))
                            .scaledFont(size: 9.5, weight: .bold, design: .rounded)
                            .foregroundStyle(AppTheme.textPrimary.opacity(0.86))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(.white.opacity(0.045), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(.white.opacity(0.06), lineWidth: 0.6)
                    }
                }

                rangeToggle
            }

            DailySpendChart(
                days: days,
                average: average,
                hoveredDate: $hoveredDate
            )
            .frame(height: 178)
            .padding(.top, 14)

            HStack {
                HStack(spacing: 5) {
                    Circle().fill(AppTheme.mint).frame(width: 4, height: 4)
                    Text("每日消费")
                    Rectangle().fill(.white.opacity(0.14)).frame(width: 12, height: 0.6)
                    Text("区间日均线 \(currency(average))")
                }
                .scaledFont(size: 8.5, weight: .medium)
                .foregroundStyle(AppTheme.textTertiary)

                Spacer()

                Text("悬停柱形查看当日金额 · 单位：元")
                    .scaledFont(size: 8.5)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.top, 8)
        }
        .padding(18)
        .glassPanel(cornerRadius: 24, tint: AppTheme.aqua)
    }

    private var rangeToggle: some View {
        HStack(spacing: 2) {
            ForEach([14, 30], id: \.self) { value in
                Button {
                    withAnimation(.smooth(duration: 0.28)) {
                        rangeDays = value
                        hoveredDate = nil
                    }
                } label: {
                    Text("\(value) 天")
                        .scaledFont(size: 9.5, weight: .semibold)
                        .foregroundStyle(rangeDays == value ? AppTheme.aqua : AppTheme.textTertiary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background {
                            if rangeDays == value {
                                Capsule()
                                    .fill(AppTheme.aqua.opacity(0.12))
                                    .overlay {
                                        Capsule().strokeBorder(AppTheme.aqua.opacity(0.20), lineWidth: 0.6)
                                    }
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(.white.opacity(0.035), in: Capsule())
    }

    private func compositionCard(_ snapshot: BillingSnapshot) -> some View {
        let slices = snapshot.gpuConsumption(days: 30)
        let total = slices.reduce(0) { $0 + $1.amount }
        let palette: [Color] = [AppTheme.mint, AppTheme.aqua, AppTheme.violet, AppTheme.amber, AppTheme.rose]

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowLabel(text: "Where It Goes", tint: AppTheme.violet)
                    Text("消费构成")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                }
                Spacer()
                Text("近 30 天")
                    .scaledFont(size: 8.5, weight: .semibold)
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.045), in: Capsule())
            }

            if slices.isEmpty {
                EmptyStateView(
                    symbol: "chart.pie",
                    title: "暂无消费构成",
                    message: "实例产生消费后，这里会按 GPU 型号拆分。"
                )
                .frame(height: 250)
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(Array(slices.prefix(5).enumerated()), id: \.element.id) { index, slice in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(palette[index % palette.count])
                                .frame(width: max(3, geometry.size.width * CGFloat(slice.amount / max(total, 0.01))))
                        }
                    }
                }
                .frame(height: 9)
                .clipShape(Capsule())
                .padding(.top, 16)

                VStack(spacing: 0) {
                    ForEach(Array(slices.prefix(5).enumerated()), id: \.element.id) { index, slice in
                        HStack(spacing: 9) {
                            Circle()
                                .fill(palette[index % palette.count])
                                .frame(width: 6, height: 6)
                                .shadow(color: palette[index % palette.count].opacity(0.5), radius: 3)

                            Text(slice.label)
                                .scaledFont(size: 10.5, weight: .medium)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text("\(Int((slice.amount / max(total, 0.01) * 100).rounded()))%")
                                .scaledFont(size: 9, weight: .medium)
                                .foregroundStyle(AppTheme.textTertiary)
                                .monospacedDigit()

                            Text(currency(slice.amount))
                                .scaledFont(size: 10.5, weight: .semibold, design: .rounded)
                                .foregroundStyle(AppTheme.textPrimary.opacity(0.86))
                                .monospacedDigit()
                                .frame(width: 70, alignment: .trailing)
                        }
                        .padding(.vertical, 10)

                        if slice.id != slices.prefix(5).last?.id {
                            Rectangle()
                                .fill(.white.opacity(0.045))
                                .frame(height: 0.6)
                                .padding(.leading, 15)
                        }
                    }
                }
                .padding(.top, 6)

                Spacer(minLength: 6)

                HStack(spacing: 6) {
                    Image(systemName: "bolt.horizontal.circle")
                        .scaledFont(size: 9, weight: .semibold)
                    Text("共 \(snapshot.chargeRecords.count) 笔消费流水 · 按 GPU 型号统计")
                        .scaledFont(size: 8.5, weight: .medium)
                }
                .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(cornerRadius: 24, tint: AppTheme.violet)
    }

    private func recentBillsCard(_ snapshot: BillingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowLabel(text: "Recent Ledger", tint: AppTheme.amber)
                    Text("最近账单")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                }
                Spacer()
                Button {
                    AppLinks.openBillingConsole()
                } label: {
                    HStack(spacing: 3) {
                        Text("全部")
                        Image(systemName: "chevron.right")
                            .scaledFont(size: 7, weight: .bold)
                    }
                    .scaledFont(size: 9, weight: .semibold)
                    .foregroundStyle(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                ForEach(Array(snapshot.recentRecords.prefix(8))) { record in
                    BillingRecordRow(record: record)

                    if record.id != snapshot.recentRecords.prefix(8).last?.id {
                        Rectangle()
                            .fill(.white.opacity(0.045))
                            .frame(height: 0.6)
                            .padding(.leading, 36)
                    }
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(cornerRadius: 24, tint: AppTheme.amber)
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
                .tint(AppTheme.amber)
            Text("正在读取 AutoDL 账单…")
                .scaledFont(size: 11.5, weight: .medium)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
        .glassPanel(cornerRadius: 24, tint: AppTheme.amber)
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.amber.opacity(0.08))
                    .frame(width: 74, height: 74)
                Image(systemName: "receipt")
                    .scaledFont(size: 27, weight: .light)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Text("还没有消费账单")
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(AppTheme.textPrimary)
            Text("实例开机产生费用后，每日柱状图、消费构成和流水会出现在这里。")
                .scaledFont(size: 11.5)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                AppLinks.openBillingConsole()
            } label: {
                HStack(spacing: 6) {
                    Text("打开 AutoDL 账单")
                    Image(systemName: "arrow.up.right")
                        .scaledFont(size: 8, weight: .bold)
                }
            }
            .buttonStyle(ActionButtonStyle(tint: AppTheme.amber, prominent: true))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .glassPanel(cornerRadius: 26, tint: AppTheme.amber)
    }

    private func errorCard(_ error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .scaledFont(size: 24, weight: .light)
                .foregroundStyle(AppTheme.amber)
            Text("账单同步失败")
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(AppTheme.textPrimary)
            Text(error)
                .scaledFont(size: 11)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("重新同步") {
                model.refreshBilling(force: true)
            }
            .buttonStyle(ActionButtonStyle(tint: AppTheme.amber, prominent: true))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
        .glassPanel(cornerRadius: 26, tint: AppTheme.amber)
    }

    private func warningBanner(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .scaledFont(size: 10, weight: .semibold)
                .foregroundStyle(AppTheme.amber)
            Text("账单刷新失败，正在展示上次数据：\(message)")
                .scaledFont(size: 10, weight: .medium)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
            Spacer()
            Button("重试") { model.refreshBilling(force: true) }
                .scaledFont(size: 10, weight: .semibold)
                .foregroundStyle(AppTheme.mint)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassPanel(cornerRadius: 14, tint: AppTheme.amber)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(width: 0.6, height: 26)
    }

    private func summaryStat(
        label: String,
        value: String,
        tint: Color,
        help: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .scaledFont(size: 8.5, weight: .medium)
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .scaledFont(size: 13, weight: .bold, design: .rounded)
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .help(help ?? "")
    }

    private func currency(_ value: Double) -> String {
        AccountBalance.currency(value)
    }
}

private struct BillingRecordRow: View {
    let record: BillRecord

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(record.billType.tint.opacity(0.11))
                    .frame(width: 27, height: 27)
                Image(systemName: record.billType.symbol)
                    .scaledFont(size: 9.5, weight: .semibold)
                    .foregroundStyle(record.billType.tint.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(record.title)
                        .scaledFont(size: 10.5, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary.opacity(0.88))
                        .lineLimit(1)

                    if record.discountAmount > 0 {
                        Text("省 \(AccountBalance.currency(record.discountAmount))")
                            .scaledFont(size: 7.5, weight: .bold, design: .rounded)
                            .foregroundStyle(AppTheme.mint.opacity(0.82))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppTheme.mint.opacity(0.08), in: Capsule())
                    }
                }

                Text(record.subtitle)
                    .scaledFont(size: 8.5, weight: .medium)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(record.signedAmountLabel)
                .scaledFont(size: 11, weight: .bold, design: .rounded)
                .foregroundStyle(
                    record.billType.isOutflow
                        ? AppTheme.textPrimary.opacity(0.88)
                        : AppTheme.mint
                )
                .monospacedDigit()
        }
        .padding(.vertical, 9)
        .help(record.detailHelp)
    }
}

private struct DailySpendChart: View {
    let days: [DailySpend]
    let average: Double
    @Binding var hoveredDate: Date?

    private var maxValue: Double {
        max(days.map(\.amount).max() ?? 0, 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let spacing: CGFloat = days.count > 20 ? 3 : 6
                let count = max(days.count, 1)
                let slot = max(2, (geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
                let barWidth = max(3, min(15, slot * 0.64))

                ZStack(alignment: .topLeading) {
                    gridLines(size: geometry.size)

                    if average > 0.005 {
                        let y = geometry.size.height - CGFloat(average / maxValue) * geometry.size.height
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                        .stroke(
                            .white.opacity(0.16),
                            style: StrokeStyle(lineWidth: 0.6, dash: [3, 4])
                        )
                    }

                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(days) { day in
                            let height = max(2, geometry.size.height * CGFloat(day.amount / maxValue))
                            let isHovered = hoveredDate == day.date
                            let isToday = AppTime.calendar.isDateInToday(day.date)

                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                    .fill(barGradient(isHovered: isHovered, isToday: isToday))
                                    .frame(width: barWidth, height: height)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                            .strokeBorder(
                                                isHovered ? .white.opacity(0.55) : .white.opacity(0.06),
                                                lineWidth: 0.6
                                            )
                                    }
                                    .shadow(
                                        color: isHovered
                                            ? AppTheme.mint.opacity(0.55)
                                            : (isToday ? AppTheme.amber.opacity(0.24) : .clear),
                                        radius: 6,
                                        y: 1
                                    )
                            }
                            .frame(width: slot, height: geometry.size.height, alignment: .bottom)
                            .contentShape(Rectangle())
                            .onHover { inside in
                                if inside {
                                    hoveredDate = day.date
                                } else if hoveredDate == day.date {
                                    hoveredDate = nil
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 148)

            HStack(spacing: days.count > 20 ? 3 : 6) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Text(label(for: index, day: day))
                        .scaledFont(size: 7.5, weight: .medium, design: .rounded)
                        .foregroundStyle(
                            AppTime.calendar.isDateInToday(day.date)
                                ? AppTheme.amber.opacity(0.85)
                                : AppTheme.textTertiary
                        )
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                        .opacity(showsLabel(index) ? 1 : 0)
                }
            }
            .frame(height: 14)
        }
    }

    private func barGradient(isHovered: Bool, isToday: Bool) -> LinearGradient {
        if isHovered {
            return LinearGradient(
                colors: [AppTheme.mint, AppTheme.aqua.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        if isToday {
            return LinearGradient(
                colors: [AppTheme.amber.opacity(0.92), AppTheme.amber.opacity(0.34)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [AppTheme.mint.opacity(0.72), AppTheme.aqua.opacity(0.22)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func gridLines(size: CGSize) -> some View {
        ForEach(0..<4, id: \.self) { index in
            let y = size.height * CGFloat(index) / 3
            Rectangle()
                .fill(.white.opacity(index == 3 ? 0.09 : 0.045))
                .frame(height: 0.5)
                .offset(y: min(y, size.height - 0.5))
        }
    }

    private func showsLabel(_ index: Int) -> Bool {
        if index == days.count - 1 { return true }
        if days.count > 20 { return index % 7 == 0 }
        return index % 3 == 0
    }

    private func label(for index: Int, day: DailySpend) -> String {
        guard showsLabel(index) else { return "" }
        return AppFormat.chartDay.string(from: day.date)
    }
}
