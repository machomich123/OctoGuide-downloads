using System;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Xml;

namespace TortoiseCrew
{
    internal static class LoginRegressionTests
    {
        private static void Check(bool ok, string label)
        { if (!ok) throw new Exception(label); Console.WriteLine("PASS: " + label); }
        public static int Main(string[] args)
        {
            try
            {
                Check(AccountLoginPolicy.RequiresVerification(null, "MICHAEL"), "legacy vault requires verification once");
                Check(!AccountLoginPolicy.RequiresVerification("MICHAEL", "MICHAEL"), "same verified account remains automatic");
                Check(AccountLoginPolicy.RequiresVerification("MICHAEL", "AUGUST"), "switching account requires its password");
                Check(AccountLoginPolicy.RequiresVerification("AUGUST", "MICHAEL"), "switching back cannot reuse the other saved account");
                Check(AccountLoginPolicy.RequiresVerification("MICHAEL", ""), "empty account cannot authorize login");
                Check(AccountLoginPolicy.RequiresVerification("MICHAEL", "STRANGER"), "unknown accounts cannot authorize login");
                var info = GameLogin.StartInfo(@"C:\Games & Mods\WoW.exe");
                Check(info.Arguments == "" && !info.UseShellExecute && info.FileName == @"C:\Games & Mods\WoW.exe", "direct startup without password or loader arguments");
                Check(!new LauncherSettings().AutoLogin, "manual login default");
                Check(typeof(GameLogin).Assembly.GetManifestResourceNames().Length == 0, "no embedded loader");
                string root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
                try {
                    string file = FailureDiagnostics.Write(root, FailureStage.GameStartup, new System.ComponentModel.Win32Exception(1260, "PASSWORD_SENTINEL"));
                    string json = File.ReadAllText(file);
                    Check(json.Contains("1260") && json.Contains("GameStartup"), "Windows code and startup stage recorded");
                    Check(!json.Contains("SENTINEL"), "exception message not logged");
                    Check(FailureDiagnostics.Category(new System.ComponentModel.Win32Exception(5)) == "AccessDenied", "access failure classification");
                    for(int i=0;i<25;i++) FailureDiagnostics.Write(root, FailureStage.GameExit, null, -1073741819);
                    Check(Directory.GetFiles(root).Length == 20, "bounded failure history");
                } finally { Directory.Delete(root, true); }
                return 0;
            }
            catch(Exception ex) { Console.Error.WriteLine(ex); return 1; }
        }
    }
}
