using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading.Tasks;
using System.Xml;

namespace TortoiseCrew
{
    // One launch, one protected payload, consumed by the real login UI.
    // Passwords never enter command lines, environment variables or keyboard input.
    internal sealed class GameLogin : IDisposable
    {
        internal static readonly byte[] Entropy = Encoding.ASCII.GetBytes("TortoiseCrew/one-shot-login/v3");
        private readonly string channel;
        private readonly string binaries;
        private GameLogin(string directory)
        {
            channel = directory;
            binaries = Path.Combine(Paths.Root, "login-v3-" + Paths.Version);
        }

        internal static byte[] ProtectPayload(string account, string password)
        {
            if (!AccountLoginPolicy.ValidAccount(account) || !CrewEnrollment.ValidExistingPassword(password))
                throw new ArgumentException("Choose a Crew account and a valid account password.");
            byte[] clear = Encoding.ASCII.GetBytes(account + "\n" + password);
            try { return ProtectedData.Protect(clear, Entropy, DataProtectionScope.CurrentUser); }
            finally { Array.Clear(clear, 0, clear.Length); }
        }

        internal static void PrivateDirectory(string directory)
        {
            var security = new DirectorySecurity();
            security.SetAccessRuleProtection(true, false);
            security.AddAccessRule(new FileSystemAccessRule(WindowsIdentity.GetCurrent().User,
                FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                PropagationFlags.None, AccessControlType.Allow));
            if (!Directory.Exists(directory)) Directory.CreateDirectory(directory, security);
            else Directory.SetAccessControl(directory, security);
        }

        private void Extract(string name)
        {
            using (var input = Assembly.GetExecutingAssembly().GetManifestResourceStream("CrewLogin." + name))
            {
                if (input == null) throw new InvalidDataException("Login component missing: " + name);
                byte[] content;
                using (var memory = new MemoryStream()) { input.CopyTo(memory); content = memory.ToArray(); }
                string path = Path.Combine(binaries, name);
                bool identical = File.Exists(path) && SameBytes(content, File.ReadAllBytes(path));
                if (!identical) File.WriteAllBytes(path, content);
            }
        }

        private static bool SameBytes(byte[] left, byte[] right)
        {
            if (left.Length != right.Length) return false;
            for (int i = 0; i < left.Length; i++) if (left[i] != right[i]) return false;
            return true;
        }

        internal static string LoaderConfiguration(string game, string module)
        {
            var doc = new XmlDocument();
            var root = doc.CreateElement("wowreeb"); doc.AppendChild(root);
            var realm = doc.CreateElement("Realm"); realm.SetAttribute("Name", "CrewLogin"); root.AppendChild(realm);
            var exe = doc.CreateElement("Exe"); exe.SetAttribute("Path", game);
            exe.SetAttribute("SHA256", Paths.GoodSha256); realm.AppendChild(exe);
            var auth = doc.CreateElement("AuthServer"); auth.SetAttribute("Host", "127.0.0.1"); realm.AppendChild(auth);
            var dll = doc.CreateElement("DLL"); dll.SetAttribute("Path", module);
            dll.SetAttribute("Method", "Load"); realm.AppendChild(dll);
            return doc.OuterXml;
        }

        public static async Task<Process> StartAsync(LauncherSettings settings, string account, string password)
        {
            if (!GameDetector.IsVerified(settings.WowPath)) throw new InvalidDataException("Game client verification failed.");
            if (!settings.AutoLogin)
                return Process.Start(new ProcessStartInfo(settings.WowPath) {
                    WorkingDirectory = Path.GetDirectoryName(settings.WowPath), UseShellExecute = true });
            var directory = Path.Combine(Paths.Root, "login-" + Guid.NewGuid().ToString("N"));
            using (var launch = new GameLogin(directory))
            {
                PrivateDirectory(launch.channel);
                PrivateDirectory(launch.binaries);
                foreach (string name in new[] { "CrewLogin.dll", "wowreeb32.exe", "wowreeb32.dll", "LICENSE.txt" })
                    launch.Extract(name);
                File.WriteAllBytes(Path.Combine(directory, "credentials.bin"), ProtectPayload(account, password));
                File.WriteAllText(Path.Combine(directory, "config.xml"),
                    LoaderConfiguration(settings.WowPath, Path.Combine(launch.binaries, "CrewLogin.dll")), new UTF8Encoding(false));
                var start = new ProcessStartInfo(Path.Combine(launch.binaries, "wowreeb32.exe")) {
                    WorkingDirectory = directory, UseShellExecute = false,
                    CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden };
                start.EnvironmentVariables["WOWREEB_ENTRY"] = "CrewLogin";
                start.EnvironmentVariables["CREW_LOGIN_CHANNEL"] = directory;
                DateTime before = DateTime.UtcNow;
                using (var loader = Process.Start(start))
                {
                    if (loader == null) throw new InvalidOperationException("The game loader could not start.");
                    var clock = Stopwatch.StartNew();
                    Process game = null;
                    while (clock.Elapsed < TimeSpan.FromSeconds(30))
                    {
                        int pid;
                        string marker = Path.Combine(directory, "game.pid");
                        if (File.Exists(marker) && Int32.TryParse(File.ReadAllText(marker), out pid))
                        {
                            game = Process.GetProcessById(pid);
                            if (!String.Equals(Path.GetFullPath(game.MainModule.FileName),
                                Path.GetFullPath(settings.WowPath), StringComparison.OrdinalIgnoreCase) ||
                                game.StartTime.ToUniversalTime() < before.AddSeconds(-2))
                            { game.Dispose(); throw new InvalidDataException("Unexpected game process from login loader."); }
                            break;
                        }
                        if (loader.HasExited && loader.ExitCode != 0)
                            throw new InvalidOperationException("The game loader exited with code " + loader.ExitCode + ".");
                        await Task.Delay(25);
                    }
                    if (game == null) throw new TimeoutException("The game did not acknowledge the login module. No password was typed.");
                    try
                    {
                        // The game UI, not this timer, decides when credentials are consumed.
                        while (!game.HasExited && clock.Elapsed < TimeSpan.FromSeconds(110))
                        {
                            if (File.Exists(Path.Combine(directory, "consumed")))
                            { Paths.WriteLog("Auto-login v3: credentials delivered once to the ready game login UI."); return game; }
                            if (File.Exists(Path.Combine(directory, "unavailable"))) break;
                            await Task.Delay(25);
                        }
                        Paths.WriteLog("Auto-login v3: no credential delivery; use the game's manual login.");
                        return game;
                    }
                    catch { game.Dispose(); throw; }
                }
            }
        }

        public void Dispose()
        {
            foreach (string name in new[] { "credentials.bin", "game.pid", "consumed", "unavailable", "config.xml" })
                try { File.Delete(Path.Combine(channel, name)); } catch { }
            try { Directory.Delete(channel); } catch { }
        }
    }

    internal static class AccountLoginPolicy
    {
        internal static bool ValidAccount(string account)
        { return account == "MICHAEL" || account == "JAYKE" || account == "BERNARD" || account == "AUGUST"; }
        internal static bool RequiresVerification(string remembered, string requested)
        { return !ValidAccount(requested) || !String.Equals(remembered, requested, StringComparison.Ordinal); }
    }
}
