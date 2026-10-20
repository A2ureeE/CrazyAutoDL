using System.Drawing;
using System.Diagnostics;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Globalization;
using Forms = System.Windows.Forms;
namespace HuNaoAutoDL.Windows;
public partial class MainWindow : Window
{
    readonly AppModel model; readonly bool demo; readonly Forms.NotifyIcon tray; bool exiting;
    int billingDays = 14;
    public MainWindow(){InitializeComponent();demo=Environment.GetCommandLineArgs().Any(x=>x.Equals("--demo",StringComparison.OrdinalIgnoreCase));model=new AppModel(demo);PollIntervalBox.Text=model.PollIntervalSeconds.ToString(CultureInfo.InvariantCulture);BalanceThresholdBox.Text=model.LowBalanceThreshold.ToString("0.##",CultureInfo.InvariantCulture);DataContext=model;InstancesGrid.ItemsSource=model.Instances;ActivityList.ItemsSource=model.Activity;BillsGrid.ItemsSource=model.Bills;tray=new Forms.NotifyIcon{Icon=SystemIcons.Application,Text="胡闹AutoDL",Visible=true};var menu=new Forms.ContextMenuStrip();menu.Items.Add("打开主窗口",null,(_,_)=>Dispatcher.Invoke(()=>{Show();WindowState=WindowState.Normal;Activate();}));menu.Items.Add("刷新数据",null,async(_,_)=>await Dispatcher.InvokeAsync(async()=>await model.RefreshAsync()));menu.Items.Add("打开 AutoDL 控制台",null,(_,_)=>OpenConsole());menu.Items.Add("退出",null,(_,_)=>Dispatcher.Invoke(()=>{exiting=true;tray.Visible=false;System.Windows.Application.Current.Shutdown();}));tray.ContextMenuStrip=menu;tray.DoubleClick+=(_,_)=>Dispatcher.Invoke(()=>{Show();WindowState=WindowState.Normal;Activate();});Loaded+=async(_,_)=>{if(!demo){var token=TokenStore.Load();if(token!=null){await model.SignInAsync(token);}else ShowLogin();}UpdateUi();};model.PropertyChanged+=(_,_)=>Dispatcher.Invoke(UpdateUi);model.NotificationRequested+=(title,body)=>tray.ShowBalloonTip(5000,title,body,Forms.ToolTipIcon.Info);Closing+=(_,e)=>{if(!exiting){e.Cancel=true;Hide();return;}model.Dispose();tray.Visible=false;tray.Dispose();};}
    void ShowLogin(){Tabs.SelectedIndex=3;TokenBox.Focus();}
    async void Login_Click(object s,RoutedEventArgs e){var token=TokenBox.Password.Trim();if(token.Length==0){ErrorText.Text="请输入 AutoDL Token";return;}await model.SignInAsync(token);UpdateUi();}
    async void WebLogin_Click(object s,RoutedEventArgs e)
    {
        var dialog = new Window { Title="AutoDL 登录", Width=960, Height=720, Owner=this, WindowStartupLocation=WindowStartupLocation.CenterOwner };
        var web = new WebView2(); dialog.Content = web;
        try
        {
            await web.EnsureCoreWebView2Async();
            await web.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(TokenCaptureScript);
            web.CoreWebView2.WebMessageReceived += async (_, args) =>
            {
                try { var token = System.Text.Json.JsonDocument.Parse(args.WebMessageAsJson).RootElement.GetProperty("token").GetString(); if (!string.IsNullOrWhiteSpace(token)) { dialog.Close(); TokenBox.Password = token; await model.SignInAsync(token); UpdateUi(); } } catch { }
            };
            web.Source = new Uri("https://www.autodl.com/login");
            dialog.ShowDialog();
        }
        catch { Process.Start(new ProcessStartInfo("https://www.autodl.com/login") { UseShellExecute=true }); }
    }
    async void Refresh_Click(object s,RoutedEventArgs e){await model.RefreshAsync();UpdateUi();}
    void Logout_Click(object s,RoutedEventArgs e){model.SignOut();ShowLogin();UpdateUi();}
    void OpenConsole(){Process.Start(new ProcessStartInfo("https://www.autodl.com/console/instance/list"){UseShellExecute=true});}
    void ApplySettings_Click(object s,RoutedEventArgs e){if(int.TryParse(PollIntervalBox.Text,out var sec)&&double.TryParse(BalanceThresholdBox.Text,out var threshold)){model.ApplySettings(sec,threshold);ErrorText.Text="设置已应用";}else ErrorText.Text="请输入有效数字";}
    void TestNotification_Click(object s,RoutedEventArgs e){tray.ShowBalloonTip(5000,"胡闹AutoDL 通知测试","Windows 系统托盘通知工作正常。",Forms.ToolTipIcon.Info);ErrorText.Text="测试通知已发送，请检查系统托盘或 Windows 通知中心。";}
    void AutoStart_Changed(object s,RoutedEventArgs e){model.AutoStart=AutoStartToggle.IsChecked==true;}
    void Instance_SelectionChanged(object s,SelectionChangedEventArgs e){if(InstancesGrid.SelectedItem is AutoDLInstance i)model.Select(i);}
    void SelectMonitor_Click(object s,RoutedEventArgs e){if(InstancesGrid.SelectedItem is AutoDLInstance i){model.Select(i);Tabs.SelectedIndex=0;}}
    async void Power_Click(object s,RoutedEventArgs e){if(InstancesGrid.SelectedItem is AutoDLInstance i)await model.TogglePowerAsync(i);}
    void Release_Click(object s,RoutedEventArgs e){OpenConsole();}
    void BillingRange_Changed(object s, SelectionChangedEventArgs e)
    {
        // SelectionChanged can fire while InitializeComponent is still wiring
        // the view, before the model field has been assigned.
        if (model is null) return;
        if (BillingRangeBox.SelectedItem is ComboBoxItem item && int.TryParse(item.Tag?.ToString(), out var days))
        {
            billingDays = days;
            UpdateBillingUi();
        }
    }
    void UpdateBillingUi()
    {
        // ComboBox selection events can fire while InitializeComponent is still
        // materializing the rest of the billing tab.
        if (DailySpendGrid is null || GpuCompositionGrid is null || BillsGrid is null) return;
        var snapshot = new BillingSnapshot(model.Bills.ToList(), model.LastUpdated ?? DateTimeOffset.Now);
        var total = snapshot.TotalSpend(billingDays);
        var daily = snapshot.DailySeries(billingDays);
        var slices = snapshot.GpuConsumption(30);
        var sliceTotal = slices.Sum(x => x.Amount);
        BillingSummary.Text = $"近 {billingDays} 天消费：¥{total:0.00} · 共 {snapshot.Records.Count} 条流水 · 同步于 {snapshot.FetchedAt.LocalDateTime:yyyy-MM-dd HH:mm}";
        BillingTodayText.Text = $"¥{snapshot.TodaySpend:0.00}";
        BillingWeekText.Text = $"¥{snapshot.Last7Spend:0.00}";
        BillingMonthText.Text = $"¥{snapshot.MonthSpend:0.00}";
        BillingAverageText.Text = $"¥{(daily.Count == 0 ? 0 : total / daily.Count):0.00}";
        DailySpendGrid.ItemsSource = daily;
        GpuCompositionGrid.ItemsSource = slices.Take(5).Select(x => new
        {
            x.Label,
            Percentage = sliceTotal <= 0 ? "0%" : $"{x.Amount / sliceTotal:P0}",
            x.AmountLabel
        }).ToList();
        BillsGrid.ItemsSource = snapshot.RecentRecords.Take(12).ToList();
    }
    void UpdateUi(){StatusText.Text=model.IsSignedIn?(demo?"演示模式":"已连接") : "未连接";TargetText.Text=model.Selected==null?"未选择":$"{model.Selected.Name} · {model.Selected.DisplayRegion}";GpuText.Text=model.Stock==null?"待同步":$"{model.Stock.IdleGpus} / {model.Stock.TotalGpus?.ToString()??"?"} 张";BalanceText.Text=model.Balance?.FormattedAvailable??"待同步";LastUpdatedText.Text=model.LastUpdated is DateTimeOffset t?$"上次同步：{t.LocalDateTime:yyyy-MM-dd HH:mm:ss}":"尚未同步";UpdateBillingUi();ErrorText.Text=model.Error??"";AutoStartToggle.IsChecked=model.AutoStart;}

    const string TokenCaptureScript = @"
(() => {
  const send = value => { if (typeof value !== 'string') return; value=value.trim(); if(value.length>=12 && !value.includes(' ')) chrome.webview.postMessage({token:value}); };
  const scan = () => { for (const key of ['token','Token','access_token','autodl_token','Authorization']) { try { send(localStorage.getItem(key)); } catch {} } };
  const oldFetch=window.fetch; if(oldFetch) window.fetch=function(...args){ return oldFetch.apply(this,args).then(r=>{ try { if(String(args[0]).includes('/api/v1/passport')) r.clone().json().then(x=>send(x?.data?.token)); } catch {} return r; }); };
  scan(); setInterval(scan,1200);
})();
";
}
