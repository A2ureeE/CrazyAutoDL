using System.IO;
using System;
namespace HuNaoAutoDL.Windows;
public static class TokenStore
{
    // LocalApplicationData is the Windows equivalent of macOS Application Support.
    // Keep the token out of roaming profiles and create the directory with the
    // user's default ACL (the profile itself is private to that user).
    static string Dir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"HuNaoAutoDL"); static string File => Path.Combine(Dir,"session.token");
    public static string? Load(){try{if(!System.IO.File.Exists(File))return null;var s=System.IO.File.ReadAllText(File).Trim();return string.IsNullOrWhiteSpace(s)?null:s;}catch{return null;}}
    public static bool Save(string token){token=token.Trim();if(token.Length==0)return false;try{Directory.CreateDirectory(Dir);System.IO.File.WriteAllText(File,token);return true;}catch{return false;}}
    public static void Delete(){try{if(System.IO.File.Exists(File))System.IO.File.Delete(File);}catch{}}
    static string PreferencesFile => Path.Combine(Dir,"preferences.json");
    public static (int PollInterval, double LowBalanceThreshold, bool AutoStart) LoadPreferences(){try{using var doc=System.Text.Json.JsonDocument.Parse(System.IO.File.ReadAllText(PreferencesFile));var r=doc.RootElement;var interval=r.TryGetProperty("pollInterval",out var i)&&i.TryGetInt32(out var iv)?iv:15;var threshold=r.TryGetProperty("lowBalanceThreshold",out var t)&&t.TryGetDouble(out var tv)?tv:20;var auto=r.TryGetProperty("autoStart",out var a)&&a.ValueKind==System.Text.Json.JsonValueKind.True;return(interval,threshold,auto);}catch{return(15,20,false);}}
    public static void SavePreferences(int interval,double threshold,bool autoStart){try{Directory.CreateDirectory(Dir);System.IO.File.WriteAllText(PreferencesFile,System.Text.Json.JsonSerializer.Serialize(new{pollInterval=interval,lowBalanceThreshold=threshold,autoStart}));}catch{}}
}
