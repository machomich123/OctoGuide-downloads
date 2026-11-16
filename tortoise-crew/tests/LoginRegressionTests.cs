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
                if (args.Length != 2) throw new ArgumentException("Pass native fixture EXE and login DLL paths.");
                Check(AccountLoginPolicy.RequiresVerification(null, "MICHAEL"), "legacy vault requires verification once");
                Check(!AccountLoginPolicy.RequiresVerification("MICHAEL", "MICHAEL"), "same verified account remains automatic");
                Check(AccountLoginPolicy.RequiresVerification("MICHAEL", "AUGUST"), "switching account requires its password");
                Check(AccountLoginPolicy.RequiresVerification("AUGUST", "MICHAEL"), "switching back cannot reuse the other saved account");
                Check(AccountLoginPolicy.RequiresVerification("MICHAEL", ""), "empty account cannot authorize login");
                Check(AccountLoginPolicy.RequiresVerification("MICHAEL", "STRANGER"), "unknown accounts cannot authorize login");
                var xml = new XmlDocument();
                xml.LoadXml(GameLogin.LoaderConfiguration(@"C:\Games & Mods\WoW.exe", @"C:\Crew\CrewLogin.dll"));
                Check(xml.SelectSingleNode("/wowreeb/Realm/Exe").Attributes["Path"].Value == @"C:\Games & Mods\WoW.exe",
                    "game paths are escaped as XML data");
                Check(!xml.OuterXml.Contains("password"), "loader configuration contains no password");
                foreach (string password in new[] { "a+^%~(){}[] !?\"Z", " leading space", "1234567890123456" })
                {
                    byte[] sealedBytes = GameLogin.ProtectPayload("MICHAEL", password);
                    byte[] clear = ProtectedData.Unprotect(sealedBytes, GameLogin.Entropy, DataProtectionScope.CurrentUser);
                    Check(Encoding.ASCII.GetString(clear) == "MICHAEL\n" + password, "DPAPI preserves exact password characters");
                    Array.Clear(clear, 0, clear.Length);
                    if (args.Length == 2)
                    {
                        string directory = Path.Combine(Path.GetTempPath(), "crew-login-test-" + Guid.NewGuid().ToString("N"));
                        GameLogin.PrivateDirectory(directory);
                        try
                        {
                            File.WriteAllBytes(Path.Combine(directory, "credentials.bin"), sealedBytes);
                            var start = new ProcessStartInfo(args[0], "\"" + args[1] + "\" \"" + directory + "\"") {
                                UseShellExecute = false, CreateNoWindow = true,
                                RedirectStandardOutput = true, RedirectStandardError = true };
                            using (var process = Process.Start(start))
                            {
                                var stdoutTask = process.StandardOutput.ReadToEndAsync();
                                var stderrTask = process.StandardError.ReadToEndAsync();
                                if (!process.WaitForExit(10000)) { process.Kill(); throw new Exception("Native fixture timed out"); }
                                string stdout = stdoutTask.GetAwaiter().GetResult();
                                string stderr = stderrTask.GetAwaiter().GetResult();
                                Check(process.ExitCode == 0, "native glue hook and one-shot DPAPI consumption: " + stdout.Trim() + stderr.Trim());
                            }
                            Check(!File.Exists(Path.Combine(directory, "credentials.bin")), "consumed credential file is deleted");
                        }
                        finally { Directory.Delete(directory, true); }
                    }
                }
                bool invalid = false;
                try { GameLogin.ProtectPayload("AUGUST", "12345678901234567"); }
                catch (ArgumentException) { invalid = true; }
                Check(invalid, "overlength password is rejected, never truncated");
                return 0;
            }
            catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
        }
    }
}
