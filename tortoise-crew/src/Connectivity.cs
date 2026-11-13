using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Web.Script.Serialization;

namespace TortoiseCrew
{
    public static class SshSupport
    {
        public static string SshPath
        {
            get
            {
                string path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                    @"System32\OpenSSH\ssh.exe");
                if (File.Exists(path)) return path;
                return "ssh.exe";
            }
        }

        public static string SshKeygenPath
        {
            get
            {
                string path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                    @"System32\OpenSSH\ssh-keygen.exe");
                if (File.Exists(path)) return path;
                return "ssh-keygen.exe";
            }
        }

        public static string ExistingOrNewKey(LauncherSettings config)
        {
            if (!String.IsNullOrEmpty(config.KeyPath) && File.Exists(config.KeyPath))
                return config.KeyPath;
            string existing = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                @".ssh\wow-altare");
            string chosen = File.Exists(existing) ? existing : Path.Combine(Paths.Root, "id_ed25519");
            config.KeyPath = chosen;
            Paths.Save(config);
            if (File.Exists(chosen)) return chosen;
            Directory.CreateDirectory(Path.GetDirectoryName(chosen));
            var start = new ProcessStartInfo(SshKeygenPath,
                "-q -t ed25519 -N \"\" -f \"" + chosen + "\"");
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.WindowStyle = ProcessWindowStyle.Hidden;
            start.RedirectStandardError = true;
            using (var proc = Process.Start(start))
            {
                if (!proc.WaitForExit(12000))
                {
                    proc.Kill();
                    throw new InvalidOperationException("Tidsavbrudd ved oppretting av SSH-nøkkel.");
                }
                if (proc.ExitCode != 0 || !File.Exists(chosen))
                    throw new InvalidOperationException("Fant ikke ssh-keygen.exe. Aktiver OpenSSH Client i Windows.");
            }
            Paths.WriteLog("Local SSH key generated, private key remains on this PC.");
            return chosen;
        }

        public static string PublicKey(LauncherSettings config)
        {
            string privatePath = ExistingOrNewKey(config);
            var publicPath = privatePath + ".pub";
            if (File.Exists(publicPath))
                return File.ReadAllText(publicPath).Trim();
            // Derive the public portion without ever returning the private key.
            var psi = new ProcessStartInfo(SshKeygenPath, "-y -f \"" + privatePath + "\"");
            psi.UseShellExecute = false;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.CreateNoWindow = true;
            using (var p = Process.Start(psi))
            {
                var output = p.StandardOutput.ReadToEnd().Trim();
                p.WaitForExit(12000);
                if (p.ExitCode == 0 && output.StartsWith("ssh-ed25519 "))
                    return output;
            }
            throw new InvalidOperationException("Kunne ikke hente offentlig SSH-nøkkel.");
        }

        public static bool PortOpen(string host, int port, int timeoutMs)
        {
            try
            {
                using (var client = new TcpClient())
                {
                    var connect = client.ConnectAsync(host, port);
                    return connect.Wait(timeoutMs) && client.Connected;
                }
            }
            catch { return false; }
        }

        public static bool WorldChallenge()
        {
            try
            {
                using (var client = new TcpClient())
                {
                    var task = client.ConnectAsync("127.0.0.1", 8085);
                    if (!task.Wait(800)) return false;
                    var stream = client.GetStream();
                    stream.ReadTimeout = 900;
                    byte[] bytes = new byte[4];
                    int count = 0;
                    while (count < 4)
                    {
                        int n = stream.Read(bytes, count, bytes.Length - count);
                        if (n == 0) return false;
                        count += n;
                    }
                    return bytes[2] == 0xEC && bytes[3] == 0x01;
                }
            }
            catch { return false; }
        }

        public static Process StartTunnel(LauncherSettings settings)
        {
            if (!Regex.IsMatch(settings.Host ?? "", @"^[A-Za-z0-9.-]+$") ||
                settings.SshPort < 1 || settings.SshPort > 65535 ||
                settings.AuthPort < 1 || settings.AuthPort > 65535 ||
                settings.WorldPort < 1 || settings.WorldPort > 65535)
                throw new InvalidOperationException("Ugyldig serveradresse eller port fra oppsett.");
            string key = ExistingOrNewKey(settings);
            string args = "-N -T -F NUL -o BatchMode=yes -o IdentitiesOnly=yes " +
                "-o StrictHostKeyChecking=accept-new -o ExitOnForwardFailure=yes " +
                "-o ConnectTimeout=9 -o ServerAliveInterval=20 -o ServerAliveCountMax=3 " +
                "-i \"" + key + "\" -p " + settings.SshPort + " " +
                "-L 127.0.0.1:3724:127.0.0.1:" + settings.AuthPort + " " +
                "-L 127.0.0.1:8085:127.0.0.1:" + settings.WorldPort + " " +
                "root@" + settings.Host;
            var psi = new ProcessStartInfo(SshPath, args);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WindowStyle = ProcessWindowStyle.Hidden;
            psi.RedirectStandardError = true;
            return Process.Start(psi);
        }

        public static async Task<bool> ProbeGameAsync(LauncherSettings settings)
        {
            if (!File.Exists(settings.KeyPath ?? "")) return false;
            return await Task.Run(() =>
            {
                var psi = new ProcessStartInfo(SshPath,
                    "-F NUL -o BatchMode=yes -o IdentitiesOnly=yes " +
                    "-o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 " +
                    "-i \"" + settings.KeyPath + "\" -p " + settings.SshPort +
                    " -W 127.0.0.1:" + settings.WorldPort + " root@" + settings.Host);
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                Process p = null;
                try
                {
                    p = Process.Start(psi);
                    using (var output = p.StandardOutput.BaseStream)
                    {
                        var buffer = new byte[4];
                        int at = 0;
                        var read = Task.Run(() =>
                        {
                            while (at < 4)
                            {
                                int n = output.Read(buffer, at, 4 - at);
                                if (n == 0) break;
                                at += n;
                            }
                        });
                        if (!read.Wait(8500)) return false;
                        return at == 4 && buffer[2] == 0xEC && buffer[3] == 0x01;
                    }
                }
                catch { return false; }
                finally
                {
                    if (p != null)
                    {
                        try { if (!p.HasExited) p.Kill(); } catch { }
                        p.Dispose();
                    }
                }
            });
        }
    }

    public static class RemoteUpdates
    {
        public static RealmManifest Fetch()
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            string url = Paths.ManifestUrl + "?t=" + DateTime.UtcNow.Ticks;
            var request = (HttpWebRequest)WebRequest.Create(url);
            request.Method = "GET";
            request.Timeout = 8000;
            request.ReadWriteTimeout = 8000;
            request.UserAgent = "TortoiseCrewLauncher/" + Paths.Version;
            using (var response = request.GetResponse())
            using (var reader = new StreamReader(response.GetResponseStream()))
            {
                string json = reader.ReadToEnd();
                if (json.Length > 32000) throw new InvalidDataException("Oppdateringsmanifest for stort.");
                var manifest = new JavaScriptSerializer().Deserialize<RealmManifest>(json);
                if (manifest == null || String.IsNullOrEmpty(manifest.Host) ||
                    !Regex.IsMatch(manifest.Host, @"^[a-z0-9-]+\.altare\.global$", RegexOptions.IgnoreCase) ||
                    manifest.SshPort < 1 || manifest.SshPort > 65535 ||
                    manifest.AuthPort < 1 || manifest.AuthPort > 65535 ||
                    manifest.WorldPort < 1 || manifest.WorldPort > 65535 ||
                    String.IsNullOrEmpty(manifest.LauncherVersion))
                    throw new InvalidDataException("Ugyldige manifestverdier.");
                return manifest;
            }
        }

        public static bool IsNewer(RealmManifest manifest)
        {
            Version current, remote;
            return Version.TryParse(Paths.Version, out current) &&
                Version.TryParse(manifest.LauncherVersion, out remote) && remote > current;
        }

        public static void ApplyRouting(LauncherSettings settings, RealmManifest manifest)
        {
            settings.Host = manifest.Host;
            settings.SshPort = manifest.SshPort;
            settings.AuthPort = manifest.AuthPort;
            settings.WorldPort = manifest.WorldPort;
            Paths.Save(settings);
        }

        public static async Task<string> DownloadVerifiedUpdateAsync(RealmManifest manifest)
        {
            if (!IsNewer(manifest)) throw new InvalidOperationException("Ingen nyere versjon.");
            var expectedUrl = "https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/TortoiseCrewLauncher.exe";
            if (!String.Equals(manifest.LauncherUrl, expectedUrl, StringComparison.OrdinalIgnoreCase) ||
                !Regex.IsMatch(manifest.LauncherSha256 ?? "", "^[0-9a-fA-F]{64}$"))
                throw new InvalidDataException("Oppdateringen mangler en godkjent URL eller kontrollsum.");
            string candidate = Path.Combine(Paths.Root, "pending-update.exe");
            await Task.Run(() =>
            {
                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                var request = (HttpWebRequest)WebRequest.Create(expectedUrl + "?t=" + DateTime.UtcNow.Ticks);
                request.Timeout = 20000;
                request.ReadWriteTimeout = 20000;
                using (var response = request.GetResponse())
                using (var input = response.GetResponseStream())
                using (var output = File.Create(candidate))
                {
                    byte[] bytes = new byte[65536];
                    int n;
                    long count = 0;
                    while ((n = input.Read(bytes, 0, bytes.Length)) != 0)
                    {
                        count += n;
                        if (count > 35000000)
                            throw new InvalidDataException("Oppdateringsfilen er for stor.");
                        output.Write(bytes, 0, n);
                    }
                }
                string actual = GameDetector.HashOf(candidate);
                if (!String.Equals(actual, manifest.LauncherSha256, StringComparison.OrdinalIgnoreCase))
                {
                    File.Delete(candidate);
                    throw new InvalidDataException("SHA-256 stemmer ikke. Oppdatering blokkert.");
                }
            });
            return candidate;
        }
    }

    public static class AutoLogin
    {
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr handle);

        public static async Task TryLoginAsync(Process game, string username)
        {
            // Avoid injecting into unknown processes and only perform this once per game launch.
            await Task.Delay(4500);
            try
            {
                if (game.HasExited) return;
                game.Refresh();
                var handle = game.MainWindowHandle;
                if (handle == IntPtr.Zero) return;
                SetForegroundWindow(handle);
                await Task.Delay(1100);
                if (game.HasExited) return;
                // The original 1.18.1 login screen opens with username focused.
                // Config.wtf is already prefilled; send both fields for resilience.
                SendKeys.SendWait("^a");
                SendKeys.SendWait(username.ToUpperInvariant());
                SendKeys.SendWait("{TAB}");
                SendKeys.SendWait("1");
                SendKeys.SendWait("{ENTER}");
                Paths.WriteLog("Single best-effort autologin keystroke sequence sent.");
            }
            catch (Exception ex) { Paths.WriteLog("Auto login skipped: " + ex.GetType().Name); }
        }
    }
}
