using System.Globalization;
using System.Text.Json;

namespace HuNaoAutoDL.Windows;

public enum InstanceState { Running, Stopped, Starting, Stopping, Unknown }

public sealed class AutoDLInstance
{
    public string Id { get; init; } = ""; public string Name { get; init; } = "未命名实例"; public string RawStatus { get; init; } = "unknown";
    public string RegionName { get; init; } = ""; public string RegionSign { get; init; } = ""; public string GpuName { get; init; } = "GPU";
    public int GpuCount { get; init; } = 1; public string MachineId { get; init; } = ""; public string ChargeType { get; init; } = "";
    public DateTimeOffset? ReleaseAt { get; init; } public long? MemoryTotal { get; init; } public long? MemoryUsed { get; init; }
    public long? SystemDiskTotal { get; init; } public long? SystemDiskUsed { get; init; } public long? DataDiskTotal { get; init; } public long? DataDiskUsed { get; init; }
    public InstanceState State => RawStatus.ToLowerInvariant() switch { "running" => InstanceState.Running, "shutdown" or "stopped" or "poweroff" or "power_off" => InstanceState.Stopped, "starting" or "powering_on" or "creating" or "restarting" or "restart" => InstanceState.Starting, "shutting_down" or "stopping" => InstanceState.Stopping, _ => InstanceState.Unknown };
    public string StateLabel => State switch { InstanceState.Running => "运行中", InstanceState.Stopped => "已关机", InstanceState.Starting => "启动中", InstanceState.Stopping => "关机中", _ => "未知状态" };
    public string DisplayRegion => !string.IsNullOrWhiteSpace(RegionName) ? RegionName : (!string.IsNullOrWhiteSpace(RegionSign) ? RegionSign : "未知地区");
    public string ChargeLabel => ChargeType.ToLowerInvariant() switch { "payg" => "按量计费", "daily" => "包日", "weekly" => "包周", "monthly" => "包月", "" => "未知计费", _ => ChargeType };
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
        return new AutoDLInstance { Id=id!, Name=S(e,"name") ?? S(e,"instance_name") ?? "未命名实例", RawStatus=S(e,"status") ?? S(e,"instance_status") ?? "unknown", GpuName=S(e,"gpu_type_name") ?? S(e,"snapshot_gpu_type_name") ?? S(e,"gpu_name") ?? "GPU", GpuCount=Math.Max(1,I(e,"req_gpu_amount") ?? I(e,"gpu_num") ?? I(e,"gpu_amount") ?? 1), RegionSign=S(e,"region_sign") ?? S(e,"region") ?? "", RegionName=S(e,"region_name") ?? S(e,"region_alias") ?? "", MachineId=S(e,"machine_id") ?? S(e,"machine_alias") ?? "", ChargeType=S(e,"charge_type") ?? "", MemoryTotal=I64(e,"mem_limit") ?? I64(usage,"mem_limit") ?? I64(e,"mem_limit_in_byte"), MemoryUsed=I64(e,"mem_usage") ?? I64(usage,"mem_usage"), SystemDiskTotal=I64(e,"root_fs_total_size") ?? I64(usage,"root_fs_total_size"), SystemDiskUsed=I64(e,"root_fs_used_size") ?? I64(usage,"root_fs_used_size"), DataDiskTotal=I64(usage,"data_disk_total_size") ?? (expand is long x ? 50L*1024*1024*1024+x : null), DataDiskUsed=I64(usage,"data_disk_used_size"), ReleaseAt=Date(e,"rent_deadline") ?? Date(e,"expired_at") };
    }
    static string? S(JsonElement e,string n)=>e.ValueKind==JsonValueKind.Object && e.TryGetProperty(n,out var v)? v.ValueKind==JsonValueKind.String?v.GetString():v.ToString():null;
    static JsonElement O(JsonElement e,string n)=>e.ValueKind==JsonValueKind.Object&&e.TryGetProperty(n,out var v)&&v.ValueKind==JsonValueKind.Object?v:default;
    static int? I(JsonElement e,string n)=>int.TryParse(S(e,n),NumberStyles.Any,CultureInfo.InvariantCulture,out var x)?x:null;
    static long? I64(JsonElement e,string n)=>long.TryParse(S(e,n),NumberStyles.Any,CultureInfo.InvariantCulture,out var x)?x:null;
    static DateTimeOffset? Date(JsonElement e,string n)=>DateTimeOffset.TryParse(S(e,n),out var x)?x:null;
}

public sealed record GPUStock(int IdleGpus, int? TotalGpus, string MachineId, string GpuName, int RequiredGpus, DateTimeOffset CheckedAt, bool MachineFound) { public bool IsAvailable => MachineFound && IdleGpus >= RequiredGpus && IdleGpus > 0; }
public sealed record AccountBalance(double Cash, double Blocked, double Voucher, string? PaymentMethod, DateTimeOffset FetchedAt) { public double Available => Math.Max(0,Cash)+Math.Max(0,Voucher); public string FormattedAvailable=>$"¥{Available:0.00}"; }
public sealed record BillRecord(string Id, DateTimeOffset CreatedAt, string Type, double Amount, string? GpuType, string? RegionName, string? MachineId, int? ChargeDuration)
{ public bool IsOutflow => Type.Equals("charge",StringComparison.OrdinalIgnoreCase)||Type.Equals("withdraw",StringComparison.OrdinalIgnoreCase); public string SignedAmountLabel=>$"{(IsOutflow?"-":"+")}¥{Amount:0.00}"; public static BillRecord? Parse(JsonElement e){var id=S(e,"uuid")??S(e,"id");if(id==null)return null;var d=e.TryGetProperty("details",out var de)?de:default;return new BillRecord(id,Date(e,"created_at")??Date(e,"confirm_at")??DateTimeOffset.Now,S(e,"bill_type")??"charge",(D(e,"asset")??0)/1000,S(d,"gpu_type"),S(d,"region_name")??S(d,"region_sign"),S(d,"machine_id"),I(d,"charge_duration"));} static string? S(JsonElement e,string n)=>e.ValueKind==JsonValueKind.Object&&e.TryGetProperty(n,out var v)?v.ToString():null;static DateTimeOffset? Date(JsonElement e,string n)=>DateTimeOffset.TryParse(S(e,n),out var x)?x:null;static double? D(JsonElement e,string n)=>double.TryParse(S(e,n),NumberStyles.Any,CultureInfo.InvariantCulture,out var x)?x:null;static int? I(JsonElement e,string n)=>int.TryParse(S(e,n),out var x)?x:null;}
public sealed class BillingSnapshot { public IReadOnlyList<BillRecord> Records {get;} public DateTimeOffset FetchedAt {get;} public BillingSnapshot(IReadOnlyList<BillRecord> records){Records=records;FetchedAt=DateTimeOffset.Now;} public double TotalSpend(int days=30)=>Records.Where(x=>x.IsOutflow&&x.CreatedAt>=DateTimeOffset.Now.AddDays(-days)).Sum(x=>x.Amount); }
public sealed record ActivityEvent(DateTimeOffset Date, string Kind, string Title, string Detail);
