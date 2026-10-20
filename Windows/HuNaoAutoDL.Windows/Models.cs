using System.Globalization;
using System.Text.Json;

namespace HuNaoAutoDL.Windows;

public enum InstanceState { Running, Stopped, Starting, Stopping, Unknown }

public sealed class AutoDLInstance
{
    public string Id { get; init; } = ""; public string Name { get; init; } = "未命名实例"; public string RawStatus { get; init; } = "unknown";
    public string RegionName { get; init; } = ""; public string RegionSign { get; init; } = ""; public string GpuName { get; init; } = "GPU";
    public int GpuCount { get; init; } = 1; public string MachineId { get; init; } = ""; public string ChargeType { get; init; } = "";
    public DateTimeOffset? ReleaseAt { get; init; } public DateTimeOffset? StartedAt { get; init; } public DateTimeOffset? StatusAt { get; init; }
    public string? SshCommand { get; init; } public string? JupyterDomain { get; init; }
    public long? MemoryTotal { get; init; } public long? MemoryUsed { get; init; }
    public long? SystemDiskTotal { get; init; } public long? SystemDiskUsed { get; init; } public long? DataDiskTotal { get; init; } public long? DataDiskUsed { get; init; }
    public InstanceState State => RawStatus.ToLowerInvariant() switch { "running" => InstanceState.Running, "shutdown" or "stopped" or "poweroff" or "power_off" => InstanceState.Stopped, "starting" or "powering_on" or "creating" or "restarting" or "restart" => InstanceState.Starting, "shutting_down" or "stopping" => InstanceState.Stopping, _ => InstanceState.Unknown };
    public string StateLabel => State switch { InstanceState.Running => "运行中", InstanceState.Stopped => "已关机", InstanceState.Starting => "启动中", InstanceState.Stopping => "关机中", _ => "未知状态" };
    public string DisplayRegion => !string.IsNullOrWhiteSpace(RegionName) ? RegionName : (!string.IsNullOrWhiteSpace(RegionSign) ? RegionSign : "未知地区");
    public string ChargeLabel => ChargeType.ToLowerInvariant() switch { "payg" => "按量计费", "daily" => "包日", "weekly" => "包周", "monthly" => "包月", "" => "未知计费", _ => ChargeType };
    public string StartedLabel => StartedAt is DateTimeOffset t ? t.LocalDateTime.ToString("MM-dd HH:mm") : "待同步";
    public string AccessLabel => !string.IsNullOrWhiteSpace(JupyterDomain) ? JupyterDomain! : (!string.IsNullOrWhiteSpace(SshCommand) ? SshCommand! : "待同步");
    public string ReleaseCountdownLabel
    {
        get
        {
            if (ReleaseAt is not DateTimeOffset t) return "待同步";
            var days = (t.LocalDateTime.Date - DateTimeOffset.Now.LocalDateTime.Date).Days;
            return days < 0 ? "已到期" : days == 0 ? "今天" : $"{days} 天后";
        }
    }
    public string ReleaseLabel => ReleaseAt is DateTimeOffset t ? $"{t.LocalDateTime:MM-dd HH:mm} · {ReleaseCountdownLabel}" : "待同步";
    public long? MemoryFree => MemoryTotal is long t && MemoryUsed is long u ? Math.Max(0, t-u) : null;
    public long? StorageTotal => (SystemDiskTotal ?? 0) + (DataDiskTotal ?? 0) is var x && x > 0 ? x : null;
    public long? StorageFree => StorageTotal is long t ? Math.Max(0, t - (SystemDiskUsed ?? 0) - (DataDiskUsed ?? 0)) : null;
    public string MemoryFreeLabel => MemoryFree is long bytes ? FormatBytes(bytes) : "待同步";
    public string StorageFreeLabel => StorageFree is long bytes ? FormatBytes(bytes) : "待同步";
    static string FormatBytes(long bytes){const double gb=1_073_741_824;const double mb=1_048_576;return bytes>=gb?$"{bytes/gb:0.0} GB":$"{bytes/mb:0} MB";}
    public static AutoDLInstance? Parse(JsonElement e)
    {
        var id = S(e,"uuid") ?? S(e,"instance_uuid") ?? S(e,"id"); if (string.IsNullOrWhiteSpace(id)) return null;
        var usage = O(e,"usage_info"); var expand = I64(e,"expand_data_disk_size");
        var releaseDates = new[] { Date(e,"rent_deadline"), Date(e,"expired_at") }.OfType<DateTimeOffset>().ToArray();
        DateTimeOffset? releaseAt = releaseDates.Length == 0 ? null : releaseDates.Min();
        return new AutoDLInstance { Id=id!, Name=S(e,"name") ?? S(e,"instance_name") ?? "未命名实例", RawStatus=S(e,"status") ?? S(e,"instance_status") ?? "unknown", GpuName=S(e,"gpu_type_name") ?? S(e,"snapshot_gpu_type_name") ?? S(e,"snapshot_gpu_alias_name") ?? S(e,"gpu_name") ?? S(e,"gpu_type") ?? "GPU", GpuCount=Math.Max(1,I(e,"req_gpu_amount") ?? I(e,"gpu_num") ?? I(e,"gpu_amount") ?? 1), RegionSign=S(e,"region_sign") ?? S(e,"region") ?? "", RegionName=S(e,"region_name") ?? S(e,"region_alias") ?? "", MachineId=S(e,"machine_id") ?? S(e,"machine_uuid") ?? S(e,"machine_alias") ?? "", ChargeType=S(e,"charge_type") ?? "", StartedAt=Date(e,"started_at") ?? Date(e,"start_time"), StatusAt=Date(e,"status_at") ?? Date(e,"updated_at"), SshCommand=S(e,"ssh_command"), JupyterDomain=S(e,"jupyter_domain"), MemoryTotal=I64(e,"mem_limit") ?? I64(usage,"mem_limit") ?? I64(e,"mem_limit_in_byte"), MemoryUsed=I64(e,"mem_usage") ?? I64(usage,"mem_usage"), SystemDiskTotal=I64(e,"root_fs_total_size") ?? I64(usage,"root_fs_total_size"), SystemDiskUsed=I64(e,"root_fs_used_size") ?? I64(usage,"root_fs_used_size"), DataDiskTotal=I64(usage,"data_disk_total_size") ?? (expand is long x ? 50L*1024*1024*1024+x : null), DataDiskUsed=I64(usage,"data_disk_used_size"), ReleaseAt=releaseAt };
    }
    static string? S(JsonElement e,string n)=>e.ValueKind==JsonValueKind.Object && e.TryGetProperty(n,out var v)? v.ValueKind==JsonValueKind.String?v.GetString():v.ToString():null;
    static JsonElement O(JsonElement e,string n)=>e.ValueKind==JsonValueKind.Object&&e.TryGetProperty(n,out var v)&&v.ValueKind==JsonValueKind.Object?v:default;
    static int? I(JsonElement e,string n)=>int.TryParse(S(e,n),NumberStyles.Any,CultureInfo.InvariantCulture,out var x)?x:null;
    static long? I64(JsonElement e,string n)=>long.TryParse(S(e,n),NumberStyles.Any,CultureInfo.InvariantCulture,out var x)?x:null;
    static DateTimeOffset? Date(JsonElement e,string n)=>DateTimeOffset.TryParse(S(e,n),out var x)?x:null;
}

public sealed record GPUStock(int IdleGpus, int? TotalGpus, string MachineId, string GpuName, int RequiredGpus, DateTimeOffset CheckedAt, bool MachineFound) { public bool IsAvailable => MachineFound && IdleGpus >= RequiredGpus && IdleGpus > 0; }
public sealed record AccountBalance(double Cash, double Blocked, double Voucher, string? PaymentMethod, DateTimeOffset FetchedAt) { public double Available => Math.Max(0,Cash)+Math.Max(0,Voucher); public string FormattedAvailable=>$"¥{Available:0.00}"; }
public enum BillType { Charge, Refund, Recharge, Withdraw, Other }

public sealed record BillRecord(
    string Id,
    DateTimeOffset CreatedAt,
    string Type,
    double Amount,
    string? GpuType,
    string? RegionName,
    string? MachineId,
    int? ChargeDuration,
    double PayByBalance = 0,
    double PayByVoucher = 0,
    double? BalanceAfter = null,
    DateTimeOffset? ChargeFrom = null,
    double? OriginPrice = null,
    double DiscountAmount = 0)
{
    public BillType Kind => Type.Trim().ToLowerInvariant() switch
    {
        "charge" => BillType.Charge,
        "refund" => BillType.Refund,
        "recharge" => BillType.Recharge,
        "withdraw" => BillType.Withdraw,
        _ => BillType.Other
    };

    public bool IsOutflow => Kind is BillType.Charge or BillType.Withdraw;
    public bool IsCharge => Kind == BillType.Charge;
    public DateTimeOffset EffectiveDate => ChargeFrom ?? CreatedAt;
    public string SignedAmountLabel => $"{(IsOutflow ? "-" : "+")}¥{Amount:0.00}";
    public string TypeLabel => Kind switch
    {
        BillType.Charge => "GPU 消费",
        BillType.Refund => "账单退款",
        BillType.Recharge => "账户充值",
        BillType.Withdraw => "账户提现",
        _ => Type
    };
    public string Title => Kind == BillType.Charge && !string.IsNullOrWhiteSpace(GpuType)
        ? (string.IsNullOrWhiteSpace(RegionName) ? GpuType! : $"{GpuType} · {RegionName}")
        : TypeLabel;
    public string DurationLabel => FormatDuration(ChargeDuration);
    public string DetailHelp
    {
        get
        {
            var parts = new List<string>();
            if (PayByBalance > 0) parts.Add($"余额支付 ¥{PayByBalance:0.00}");
            if (PayByVoucher > 0) parts.Add($"代金券 ¥{PayByVoucher:0.00}");
            if (OriginPrice is > 0 && DiscountAmount > 0) parts.Add($"原价 ¥{OriginPrice:0.00} · 优惠 ¥{DiscountAmount:0.00}");
            if (BalanceAfter is double balance) parts.Add($"支付后余额 ¥{balance:0.00}");
            if (!string.IsNullOrWhiteSpace(MachineId)) parts.Add($"主机 {MachineId}");
            return string.Join(" · ", parts);
        }
    }

    public static BillRecord? Parse(JsonElement e)
    {
        var id = S(e, "uuid") ?? S(e, "id");
        if (string.IsNullOrWhiteSpace(id)) return null;
        var details = e.TryGetProperty("details", out var d) ? d : default;
        var discount = e.TryGetProperty("discount_detail", out var dd) ? dd : default;
        return new BillRecord(
            id!,
            Date(e, "created_at") ?? Date(e, "confirm_at") ?? DateTimeOffset.Now,
            S(e, "bill_type") ?? "charge",
            Math.Max(0, (D(e, "asset") ?? 0) / 1000),
            S(details, "gpu_type"),
            S(details, "region_name") ?? S(details, "region_sign"),
            S(details, "machine_id"),
            I(details, "charge_duration"),
            (D(e, "pay_by_balance") ?? 0) / 1000,
            (D(e, "pay_by_voucher") ?? 0) / 1000,
            D(e, "balance") is double balance ? balance / 1000 : null,
            Date(details, "charge_from"),
            D(discount, "origin_price") is double originPrice ? originPrice / 1000 : null,
            (D(discount, "discount_sum") ?? 0) / 1000);
    }

    static string? S(JsonElement e, string n) => e.ValueKind == JsonValueKind.Object && e.TryGetProperty(n, out var v) ? v.ToString() : null;
    static DateTimeOffset? Date(JsonElement e, string n) => DateTimeOffset.TryParse(S(e, n), CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal, out var x) ? x : null;
    static double? D(JsonElement e, string n) => double.TryParse(S(e, n), NumberStyles.Any, CultureInfo.InvariantCulture, out var x) ? x : null;
    static int? I(JsonElement e, string n) => int.TryParse(S(e, n), NumberStyles.Any, CultureInfo.InvariantCulture, out var x) ? x : null;
    static string FormatDuration(int? duration)
    {
        if (duration is not > 0) return "";
        if (duration >= 3600)
        {
            var minutes = duration.Value % 3600 / 60;
            return minutes == 0 ? $"{duration.Value / 3600} 小时" : $"{duration.Value / 3600} 小时 {minutes} 分";
        }
        return duration >= 60 ? $"{duration.Value / 60} 分钟" : $"{duration.Value} 秒";
    }
}

public sealed record DailySpend(DateTimeOffset Date, double Amount)
{
    public string DateLabel => Date.ToString("MM-dd", CultureInfo.InvariantCulture);
    public string AmountLabel => $"¥{Amount:0.00}";
}

public sealed record ConsumptionSlice(string Label, double Amount)
{
    public string AmountLabel => $"¥{Amount:0.00}";
    public string Percentage { get; init; } = "—";
}

public sealed class BillingSnapshot
{
    public IReadOnlyList<BillRecord> Records { get; }
    public DateTimeOffset FetchedAt { get; }
    public IReadOnlyList<BillRecord> ChargeRecords => Records.Where(x => x.IsCharge).ToList();
    public IReadOnlyList<BillRecord> RecentRecords => Records.OrderByDescending(x => x.CreatedAt).Take(12).ToList();

    public BillingSnapshot(IReadOnlyList<BillRecord> records, DateTimeOffset? fetchedAt = null)
    {
        Records = records;
        FetchedAt = fetchedAt ?? DateTimeOffset.Now;
    }

    public double NetSpend(DateTimeOffset day)
    {
        var key = day.LocalDateTime.Date;
        var total = Records.Where(x => x.EffectiveDate.LocalDateTime.Date == key).Sum(x => NetContribution(x));
        return Math.Max(0, total);
    }

    public double NetSpendSince(DateTimeOffset start)
    {
        var key = start.LocalDateTime.Date;
        var total = Records.Where(x => x.EffectiveDate.LocalDateTime.Date >= key).Sum(x => NetContribution(x));
        return Math.Max(0, total);
    }

    public IReadOnlyList<DailySpend> DailySeries(int days = 14)
    {
        days = Math.Clamp(days, 1, 365);
        var today = DateTimeOffset.Now.Date;
        return Enumerable.Range(0, days)
            .Select(offset => today.AddDays(-(days - 1 - offset)))
            .Select(day => new DailySpend(day, NetSpend(day)))
            .ToList();
    }

    public double TotalSpend(int days = 30)
    {
        days = Math.Max(1, days);
        return DailySeries(days).Sum(x => x.Amount);
    }

    public double TodaySpend => TotalSpend(1);
    public double Last7Spend => TotalSpend(7);
    public double MonthSpend
    {
        get
        {
            var now = DateTimeOffset.Now;
            var start = new DateTimeOffset(now.Year, now.Month, 1, 0, 0, 0, now.Offset);
            return NetSpendSince(start);
        }
    }
    public double AverageDailySpend => Last7Spend / 7;

    public int? EstimatedDaysRemaining(double? balance)
        => balance is > 0 && AverageDailySpend > 0.01 ? Math.Max(0, (int)(balance.Value / AverageDailySpend)) : null;

    public IReadOnlyList<ConsumptionSlice> GpuConsumption(int days = 30)
    {
        var start = DateTimeOffset.Now.Date.AddDays(-(Math.Max(1, days) - 1));
        return ChargeRecords
            .Where(x => x.EffectiveDate.LocalDateTime.Date >= start)
            .GroupBy(x => string.IsNullOrWhiteSpace(x.GpuType) ? "其他消费" : x.GpuType!)
            .Select(group => new ConsumptionSlice(group.Key, group.Sum(x => x.Amount)))
            .OrderByDescending(x => x.Amount)
            .ToList();
    }

    static double NetContribution(BillRecord record) => record.Kind switch
    {
        BillType.Charge => record.Amount,
        BillType.Refund => -record.Amount,
        _ => 0
    };
}
public sealed record ActivityEvent(DateTimeOffset Date, string Kind, string Title, string Detail);
