using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace TortoiseCrew
{
    public sealed class LauncherSettings
    {
        public string Username { get; set; }
        public string WowPath { get; set; }
        public string KeyPath { get; set; }
        public bool AutoLogin { get; set; }
        public string Host { get; set; }
        public string CrewApiUrl { get; set; }
        public int SshPort { get; set; }
        public int AuthPort { get; set; }
        public int WorldPort { get; set; }

        public LauncherSettings()
        {
            Username = "";
            WowPath = "";
            KeyPath = "";
            AutoLogin = true;
            Host = "us-iad01.altare.global";
            CrewApiUrl = "";
            SshPort = 25034;
            AuthPort = 3724;
            WorldPort = 8085;
        }
    }

    public sealed class RealmManifest
    {
        public string LauncherVersion { get; set; }
        public string LauncherUrl { get; set; }
        public string LauncherSha256 { get; set; }
        public string CrewApiUrl { get; set; }
        public string Host { get; set; }
        public int SshPort { get; set; }
        public int AuthPort { get; set; }
        public int WorldPort { get; set; }
        public string Message { get; set; }
    }

    public static class Paths
    {
        public const string Version = "1.0.4";
        public const string GoodSha256 = "97EA82AB7A82ED88BC5A155AB9BBF7E0BCDB5B9F892A47C6F8EDABE1496BFC75";
        public const string ManifestUrl = "https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/manifest.json";
        public static readonly string Root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TortoiseCrewLauncher");
        public static string Executable { get { return Path.Combine(Root, "TortoiseCrewLauncher.exe"); } }
        public static string Settings { get { return Path.Combine(Root, "settings.json"); } }
        public static string Log { get { return Path.Combine(Root, "launcher.log"); } }

        public static void WriteLog(string message)
        {
            try
            {
                Directory.CreateDirectory(Root);
                File.AppendAllText(Log, DateTime.Now.ToString("s") + " " + message + Environment.NewLine, Encoding.UTF8);
            }
            catch { }
        }

        public static LauncherSettings Load()
        {
            try
            {
                if (File.Exists(Settings))
                {
                    var obj = new JavaScriptSerializer().Deserialize<LauncherSettings>(
                        File.ReadAllText(Settings, Encoding.UTF8));
                    if (obj != null)
                    {
                        if (obj.SshPort < 1 || obj.SshPort > 65535) obj.SshPort = 25034;
                        if (obj.AuthPort < 1 || obj.AuthPort > 65535) obj.AuthPort = 3724;
                        if (obj.WorldPort < 1 || obj.WorldPort > 65535) obj.WorldPort = 8085;
                        return obj;
                    }
                }
            }
            catch (Exception ex) { WriteLog("Settings read failed: " + ex.GetType().Name); }
            return new LauncherSettings();
        }

        public static void Save(LauncherSettings settings)
        {
            Directory.CreateDirectory(Root);
            var temp = Settings + ".new";
            File.WriteAllText(temp, new JavaScriptSerializer().Serialize(settings), Encoding.UTF8);
            File.Copy(temp, Settings, true);
            File.Delete(temp);
        }
    }

    public static class GameDetector
    {
        public static bool IsVerified(string path)
        {
            try
            {
                if (String.IsNullOrWhiteSpace(path) || !File.Exists(path) ||
                    !String.Equals(Path.GetFileName(path), "WoW.exe", StringComparison.OrdinalIgnoreCase))
                    return false;
                // Exact fingerprint of the user's confirmed working build 7272 executable.
                using (var stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                using (var sha = SHA256.Create())
                {
                    var digest = BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
                    return String.Equals(digest, Paths.GoodSha256, StringComparison.OrdinalIgnoreCase);
                }
            }
            catch { return false; }
        }

        public static string HashOf(string path)
        {
            using (var input = File.OpenRead(path))
            using (var sha = SHA256.Create())
                return BitConverter.ToString(sha.ComputeHash(input)).Replace("-", "");
        }

        private static bool LooksLikeOctoClient(string exe)
        {
            string folder = (Path.GetDirectoryName(exe) ?? "").Replace('/', '\\');
            return Regex.IsMatch(folder, @"(^|\\)(client-octo|octowow)(\\|$)", RegexOptions.IgnoreCase);
        }

        private static int ClientPreference(string exe)
        {
            var parent = Path.GetDirectoryName(exe) ?? "";
            var folder = Path.GetFileName(parent) ?? "";
            int score = 0;
            if (String.Equals(folder, "client-turtle", StringComparison.OrdinalIgnoreCase))
                score += 1000;
            else if (folder.IndexOf("turtle", StringComparison.OrdinalIgnoreCase) >= 0)
                score += 400;
            else if (folder.IndexOf("tortoise", StringComparison.OrdinalIgnoreCase) >= 0)
                score += 300;
            if (Directory.Exists(Path.Combine(parent, "Data")))
                score += 100;
            if (LooksLikeOctoClient(exe))
                score -= 1000;
            return score;
        }

        public static string Browse(string current)
        {
            using (var dialog = new OpenFileDialog())
            {
                dialog.Title = "Choose WoW.exe from Tortoise / Turtle WoW 1.18.1";
                dialog.Filter = "World of Warcraft|WoW.exe";
                dialog.FileName = "WoW.exe";
                if (!String.IsNullOrEmpty(current) && Directory.Exists(Path.GetDirectoryName(current)))
                    dialog.InitialDirectory = Path.GetDirectoryName(current);
                if (dialog.ShowDialog() == DialogResult.OK)
                {
                    if (!IsVerified(dialog.FileName))
                    {
                        MessageBox.Show("This WoW.exe does not match the verified Tortoise 1.18.1 (build 7272).\n\n" +
                            "Select WoW.exe from your client-turtle folder, not a newer or differently modified WoW client.",
                            "Wrong WoW client", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return "";
                    }
                    if (LooksLikeOctoClient(dialog.FileName))
                    {
                        var confirmation = MessageBox.Show(
                            "This appears to be an OctoWoW client folder.\n\n" +
                            "This exact WoW.exe may match build 7272, but Octo's modified assets " +
                            "previously caused missing textures and Error #132.\n\n" +
                            "Use this folder anyway?",
                            "Potentially incompatible client",
                            MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                        if (confirmation != DialogResult.Yes) return "";
                    }
                    return dialog.FileName;
                }
            }
            return "";
        }

        public static string Find(Action<int, string> progress)
        {
            var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var matches = new List<string>();
            var recent = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Recent), "");
            var hints = new List<string> {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Codex"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Games"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Games"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Games"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"),
                @"C:\Games", @"D:\Games", @"C:\Turtle WoW", @"C:\Tortoise WoW"
            };
            // A previous player-specific client path is always preferred.
            var original = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                @"Codex\2026-11-08\autonomous-project-ultimate-world-of-warcraft\work\tortoise\client-turtle\WoW.exe");
            if (IsVerified(original)) return original;

            var dirs = new Queue<string>();
            foreach (var root in hints)
                if (Directory.Exists(root)) dirs.Enqueue(root);
            foreach (var drive in DriveInfo.GetDrives())
                try { if (drive.IsReady && drive.DriveType == DriveType.Fixed) dirs.Enqueue(drive.RootDirectory.FullName); }
                catch { }

            int checkedDirs = 0;
            int maxDirs = 200000;
            var started = Stopwatch.StartNew();
            while (dirs.Count > 0 && checkedDirs < maxDirs && started.Elapsed.TotalSeconds < 80)
            {
                string dir = dirs.Dequeue();
                if (!visited.Add(dir)) continue;
                ++checkedDirs;
                if (checkedDirs % 350 == 0 && progress != null) progress(checkedDirs, dir);

                try
                {
                    string candidate = Path.Combine(dir, "WoW.exe");
                    if (File.Exists(candidate) && IsVerified(candidate))
                        matches.Add(candidate);
                }
                catch { }
                // Do not stop at an Octo folder when a verified client-turtle may exist.
                if (matches.Any(m => ClientPreference(m) >= 1000) &&
                    started.Elapsed.TotalSeconds > 5)
                    break;
                try
                {
                    foreach (var sub in Directory.EnumerateDirectories(dir))
                    {
                        try
                        {
                            var info = new DirectoryInfo(sub);
                            if ((info.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                            if (sub.EndsWith(@"\$Recycle.Bin", StringComparison.OrdinalIgnoreCase) ||
                                sub.EndsWith(@"\System Volume Information", StringComparison.OrdinalIgnoreCase) ||
                                sub.EndsWith(@"\Windows", StringComparison.OrdinalIgnoreCase))
                                continue;
                            dirs.Enqueue(sub);
                        }
                        catch { }
                    }
                }
                catch { }
            }
            if (matches.Count == 0) return "";
            // Exact executable hash is mandatory; compatible Turtle data folders
            // outrank Octo folders. Among equivalent folders prefer recent access.
            string selected = matches
                .OrderByDescending(m => ClientPreference(m))
                .ThenByDescending(m => {
                    try { return File.GetLastAccessTimeUtc(m); }
                    catch { return DateTime.MinValue; }
                })
                .First();
            // Never automatically choose the Octo client known to crash; ask the user instead.
            return LooksLikeOctoClient(selected) ? "" : selected;
        }

        public static void Configure(string exe, string username)
        {
            if (!IsVerified(exe)) throw new InvalidOperationException("WoW.exe could not be verified.");
            if (!Regex.IsMatch(username, @"^[A-Za-z0-9]{2,24}$"))
                throw new InvalidOperationException("Username must contain 2–24 letters or digits.");
            var gameDir = Path.GetDirectoryName(exe);
            var realmlist = Path.Combine(gameDir, "realmlist.wtf");
            WriteBackedUp(realmlist, "set realmlist 127.0.0.1" + Environment.NewLine);

            // Setting accountName in Config.wtf pre-fills the WoW username field.
            var configDir = Path.Combine(gameDir, "WTF");
            Directory.CreateDirectory(configDir);
            var config = Path.Combine(configDir, "Config.wtf");
            var text = File.Exists(config) ? File.ReadAllText(config) : "";
            var entry = "SET accountName \"" + username.ToUpperInvariant() + "\"";
            if (Regex.IsMatch(text, @"(?im)^\s*SET\s+accountName\s+.*$"))
                text = Regex.Replace(text, @"(?im)^\s*SET\s+accountName\s+.*$", entry);
            else
                text += Environment.NewLine + entry + Environment.NewLine;
            WriteBackedUp(config, text);
        }

        private static void WriteBackedUp(string path, string newText)
        {
            var previous = File.Exists(path) ? File.ReadAllText(path) : null;
            if (previous != null && previous.Replace("\r\n", "\n") == newText.Replace("\r\n", "\n")) return;
            if (previous != null && !File.Exists(path + ".crew-backup"))
                File.Copy(path, path + ".crew-backup");
            File.WriteAllText(path, newText, new UTF8Encoding(false));
        }
    }
}
