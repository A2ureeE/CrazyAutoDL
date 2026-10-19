import Foundation

struct DemoSeed {
    let instances: [AutoDLInstance]
    let selectedInstanceID: String
    let stock: GPUStock
    let balance: AccountBalance
    let billing: BillingSnapshot
    let activity: [ActivityEvent]
}

enum DemoData {
    private static let gigabyte: Int64 = 1_073_741_824

    static func seed() -> DemoSeed {
        let now = Date()
        let calendar = AppTime.calendar
        let today = calendar.startOfDay(for: now)
        let releaseSoon = calendar.date(byAdding: .day, value: 3, to: now)
        let releaseLater = calendar.date(byAdding: .day, value: 12, to: now)

        let lab = AutoDLInstance(
            id: "demo-8f3c1a92",
            name: "rtx4090-lab",
            rawStatus: "shutdown",
            regionName: "北京B区",
            regionSign: "beijing-b",
            gpuName: "RTX 4090",
            gpuCount: 1,
            machineID: "seetacloud-4090-07",
            chargeType: "payg",
            startedAt: nil,
            statusAt: calendar.date(byAdding: .minute, value: -18, to: now),
            sshCommand: nil,
            rootPassword: nil,
            jupyterDomain: nil,
            systemDiskTotal: 30 * gigabyte,
            systemDiskUsed: 11 * gigabyte,
            dataDiskTotal: 50 * gigabyte,
            dataDiskUsed: 19 * gigabyte,
            diskExpandAvailable: 0,
            memoryTotal: 64 * gigabyte,
            memoryUsed: 7 * gigabyte,
            releaseAt: releaseSoon
        )

        let training = AutoDLInstance(
            id: "demo-2b7d4c10",
            name: "a100-train",
            rawStatus: "running",
            regionName: "内蒙A区",
            regionSign: "neimeng-a",
            gpuName: "A100-SXM4-80GB",
            gpuCount: 1,
            machineID: "seetacloud-a100-03",
            chargeType: "payg",
            startedAt: calendar.date(byAdding: .hour, value: -3, to: now),
            statusAt: calendar.date(byAdding: .minute, value: -1, to: now),
            sshCommand: "ssh -p 22333 root@connect.example.com",
            rootPassword: nil,
            jupyterDomain: "https://jupyter.example.com",
            systemDiskTotal: 30 * gigabyte,
            systemDiskUsed: 18 * gigabyte,
            dataDiskTotal: 50 * gigabyte,
            dataDiskUsed: 36 * gigabyte,
            diskExpandAvailable: 0,
            memoryTotal: 120 * gigabyte,
            memoryUsed: 74 * gigabyte,
            releaseAt: releaseLater
        )

        let inference = AutoDLInstance(
            id: "demo-5c9e3f61",
            name: "3090-infer",
            rawStatus: "shutdown",
            regionName: "上海A区",
            regionSign: "shanghai-a",
            gpuName: "RTX 3090",
            gpuCount: 1,
            machineID: "seetacloud-3090-02",
            chargeType: "payg",
            startedAt: nil,
            statusAt: calendar.date(byAdding: .hour, value: -5, to: now),
            sshCommand: nil,
            rootPassword: nil,
            jupyterDomain: nil,
            systemDiskTotal: 30 * gigabyte,
            systemDiskUsed: 9 * gigabyte,
            dataDiskTotal: 50 * gigabyte,
            dataDiskUsed: 23 * gigabyte,
            diskExpandAvailable: 0,
            memoryTotal: 32 * gigabyte,
            memoryUsed: 4 * gigabyte,
            releaseAt: calendar.date(byAdding: .day, value: 20, to: now)
        )

        let stock = GPUStock(
            idleGPUs: 2,
            totalGPUs: 8,
            machineID: "seetacloud-4090-07",
            gpuName: "RTX 4090",
            requiredGPUs: 1,
            checkedAt: now,
            machineFound: true
        )

        let balance = AccountBalance(
            cash: 186.40,
            blocked: 12.50,
            voucher: 30.00,
            paymentMethod: "balance",
            fetchedAt: now
        )

        return DemoSeed(
            instances: [lab, training, inference],
            selectedInstanceID: lab.id,
            stock: stock,
            balance: balance,
            billing: BillingSnapshot(records: billRecords(today: today, now: now, calendar: calendar), fetchedAt: now),
            activity: [
                ActivityEvent(
                    kind: .success,
                    title: "自动开机成功",
                    detail: "RTX 4090 出现空闲，已为 rtx4090-lab 开机"
                ),
                ActivityEvent(
                    kind: .info,
                    title: "发现空闲显卡",
                    detail: "北京B区 · 2 张 RTX 4090 可用"
                ),
                ActivityEvent(
                    kind: .success,
                    title: "已自动连接 AutoDL",
                    detail: "正在守护 2 个实例"
                ),
                ActivityEvent(
                    kind: .warning,
                    title: "余额提醒阈值",
                    detail: "可用余额低于 ¥20.00 时将提醒"
                ),
                ActivityEvent(
                    kind: .info,
                    title: "账单已同步",
                    detail: "近 30 天消费构成已更新"
                )
            ]
        )
    }

    private static func billRecords(today: Date, now: Date, calendar: Calendar) -> [BillRecord] {
        var records: [BillRecord] = []
        let weekdayBase: [Int: Double] = [1: 4.6, 2: 8.2, 3: 9.6, 4: 8.8, 5: 7.1, 6: 11.4, 7: 10.2]

        for offset in (0..<35).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let base = weekdayBase[calendar.component(.weekday, from: day)] ?? 8
            let count = offset == 0 ? 1 : 3

            for index in 0..<count {
                let timestamp: Date
                if offset == 0 {
                    timestamp = calendar.date(byAdding: .minute, value: -5, to: now) ?? now
                } else {
                    timestamp = calendar.date(byAdding: .hour, value: 10 + index * 4, to: day) ?? day
                }
                let amount = base / Double(count) * (0.86 + Double((offset + index) % 4) * 0.07)
                let gpu = index == 2 ? "RTX 3090" : "RTX 4090"
                let origin = amount * 1.18

                records.append(BillRecord(
                    id: "demo-bill-\(offset)-\(index)",
                    createdAt: timestamp,
                    type: "charge",
                    amount: amount,
                    payByBalance: amount * 0.82,
                    payByVoucher: amount * 0.18,
                    balanceAfter: max(0, 216.40 - Double(34 - offset) * 7.4),
                    gpuType: gpu,
                    regionName: index == 2 ? "内蒙A区" : "北京B区",
                    machineID: index == 2 ? "seetacloud-3090-02" : "seetacloud-4090-07",
                    chargeDuration: 3600,
                    chargeFrom: timestamp,
                    originPrice: origin,
                    discountAmount: origin - amount
                ))
            }
        }

        if let rechargeDate = calendar.date(byAdding: .day, value: -9, to: today),
           let refundDate = calendar.date(byAdding: .day, value: -2, to: today) {
            records.append(BillRecord(
                id: "demo-recharge",
                createdAt: rechargeDate,
                type: "recharge",
                amount: 100,
                payByBalance: 100,
                payByVoucher: 0,
                balanceAfter: 300,
                gpuType: nil,
                regionName: nil,
                machineID: nil,
                chargeDuration: nil,
                chargeFrom: nil,
                originPrice: nil,
                discountAmount: 0
            ))
            records.append(BillRecord(
                id: "demo-refund",
                createdAt: refundDate,
                type: "refund",
                amount: 1.80,
                payByBalance: 1.80,
                payByVoucher: 0,
                balanceAfter: 231.80,
                gpuType: "RTX 4090",
                regionName: "北京B区",
                machineID: "seetacloud-4090-07",
                chargeDuration: 600,
                chargeFrom: refundDate,
                originPrice: 1.80,
                discountAmount: 0
            ))
        }

        return records
    }
}
