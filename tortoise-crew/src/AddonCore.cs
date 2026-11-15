using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace TortoiseCrew
{
    // Addon sources are data, not executable code. We only extract addons containing .toc files.
    public sealed class AddonEntry
    {
        public string Name, Description, Url, Author, Source, IconUrl;
        public int Stars;
        public bool IsPack;
    }

    internal static class AddonCatalog
    {
        private const string RegistryUrl = "https://raw.githubusercontent.com/bnema/turtlectl/main/data/addons.json";
        private static string CachePath { get { return Path.Combine(Paths.Root, "addon-registry.json"); } }
        private static object Field(Dictionary<string, object> row, string key)
        {
            object value;
            return row != null && row.TryGetValue(key, out value) ? value : null;
        }
        private static string S(Dictionary<string, object> row, string key)
        {
            return Convert.ToString(Field(row, key) ?? "");
        }
        private static int Number(Dictionary<string, object> row, string key)
        {
            int number;
            return int.TryParse(S(row, key), out number) ? number : 0;
        }
        internal static WebClient NewClient()
        {
            var client = new WebClient { Encoding = Encoding.UTF8 };
            client.Headers[HttpRequestHeader.UserAgent] = "TortoiseCrewAddonHub/1.0";
            client.Headers[HttpRequestHeader.Accept] = "application/vnd.github+json";
            return client;
        }
        internal static Task<List<AddonEntry>> LoadAsync()
        {
            return Task.Run(() =>
            {
                string json = null;
                try
                {
                    if (File.Exists(CachePath) && File.GetLastWriteTimeUtc(CachePath) > DateTime.UtcNow.AddHours(-24))
                        json = File.ReadAllText(CachePath);
                    else
                    {
                        using (var web = NewClient()) json = web.DownloadString(RegistryUrl);
                        Directory.CreateDirectory(Paths.Root);
                        File.WriteAllText(CachePath, json);
                    }
                }
                catch
                {
                    if (File.Exists(CachePath)) json = File.ReadAllText(CachePath);
                    else throw;
                }
                var parsed = new JavaScriptSerializer { MaxJsonLength = 16 * 1024 * 1024 }
                    .DeserializeObject(json) as Dictionary<string, object>;
                var records = Field(parsed, "addons") as object[];
                var items = new List<AddonEntry>();
                if (records != null)
                foreach (var record in records)
                {
                    var row = record as Dictionary<string, object>;
                    if (row == null) continue;
                    string url = S(row, "url");
                    if (String.IsNullOrWhiteSpace(url)) continue;
                    var item = new AddonEntry
                    {
                        Name = S(row, "name"),
                        Description = S(row, "description"),
                        Author = S(row, "author"),
                        Source = "Turtle WoW Wiki / GitHub",
                        Url = url,
                        Stars = Number(row, "stars")
                    };
                    if (String.IsNullOrWhiteSpace(item.Description))
                        item.Description = "Community addon for the Vanilla / Turtle WoW client.";
                    item.IconUrl = Avatar(item.Url);
                    items.Add(item);
                }
                return items.OrderByDescending(a => a.Stars).ThenBy(a => a.Name).ToList();
            });
        }
        internal static Task<List<AddonEntry>> SearchGithubAsync(string search)
        {
            return Task.Run(() =>
            {
                var q = Uri.EscapeDataString((search ?? "").Trim() + " turtle wow addon");
                using (var web = NewClient())
                {
                    var json = web.DownloadString("https://api.github.com/search/repositories?per_page=40&sort=stars&q=" + q);
                    var parsed = new JavaScriptSerializer { MaxJsonLength = 4 * 1024 * 1024 }
                        .DeserializeObject(json) as Dictionary<string, object>;
                    var rows = Field(parsed, "items") as object[];
                    var items = new List<AddonEntry>();
                    if (rows == null) return items;
                    foreach (var value in rows)
                    {
                        var row = value as Dictionary<string, object>;
                        if (row == null) continue;
                        string url = S(row, "html_url");
                        items.Add(new AddonEntry
                        {
                            Name = S(row, "name"),
                            Description = S(row, "description"),
                            Author = S(row, "full_name"),
                            Source = "GitHub search (compatibility not verified)",
                            Url = url,
                            Stars = Number(row, "stargazers_count"),
                            IconUrl = Avatar(url)
                        });
                    }
                    return items;
                }
            });
        }
        internal static string Avatar(string url)
        {
            var m = Regex.Match(url ?? "", @"^https://github\.com/([^/]+)/[^/]+", RegexOptions.IgnoreCase);
            return m.Success ? "https://github.com/" + m.Groups[1].Value + ".png?size=96" : "";
        }
        internal static List<AddonEntry> Packs()
        {
            return new List<AddonEntry>
            {
                new AddonEntry { Name="Comfy Atmosphere", Description="Import an existing atmosphere/visual patch pack (.MPQ) from OctoWoW or a local archive.", Source="Local game patch", IsPack=true },
                new AddonEntry { Name="HD Switch / HD Pack", Description="Import locally installed HD patches. MPQ packs can conflict with the verified 1.18.1 client.", Source="Local game patch", IsPack=true },
                new AddonEntry { Name="Nampower & client DLLs", Description="Import compatible local DLLs and merge dlls.txt without erasing existing entries.", Source="Local client extension", IsPack=true },
                new AddonEntry { Name="VanillaFixes", Description="Import an existing VanillaFixes.exe into the game folder (not launched automatically).", Source="Local client extension", IsPack=true }
            };
        }
    }

    internal sealed class InstalledAddon
    {
        public string Name, Folder, Dependencies, MissingDependencies;
    }

    internal static class AddonFiles
    {
        private static readonly Regex RepoPattern = new Regex(
            @"^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

        internal static string GameRoot(string wowExe)
        {
            if (!GameDetector.IsVerified(wowExe))
                throw new InvalidOperationException("First choose a verified 1.18.1 / build 7272 WoW.exe on the Realm page.");
            return Path.GetDirectoryName(wowExe);
        }
        internal static string AddonRoot(string wowExe)
        {
            return Path.Combine(GameRoot(wowExe), "Interface", "AddOns");
        }
        internal static List<InstalledAddon> Installed(string wowExe)
        {
            var root = AddonRoot(wowExe);
            var list = new List<InstalledAddon>();
            if (!Directory.Exists(root)) return list;
            foreach (var dir in Directory.GetDirectories(root))
            {
                var tocs = Directory.GetFiles(dir, "*.toc", SearchOption.TopDirectoryOnly);
                if (tocs.Length == 0) continue;
                var deps = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                var required = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var toc in tocs)
                foreach (var line in File.ReadAllLines(toc))
                {
                    var match = Regex.Match(line, @"^##\s*(?:Dependencies|RequiredDeps|OptionalDeps)\s*:\s*(.*)$",
                        RegexOptions.IgnoreCase);
                    if (match.Success)
                        foreach (var dep in match.Groups[1].Value.Split(','))
                            if (!String.IsNullOrWhiteSpace(dep))
                            {
                                deps.Add(dep.Trim());
                                if (line.IndexOf("OptionalDeps", StringComparison.OrdinalIgnoreCase) < 0)
                                    required.Add(dep.Trim());
                            }
                }
                list.Add(new InstalledAddon
                {
                    Name = Path.GetFileName(dir),
                    Folder = dir,
                    Dependencies = String.Join(", ", deps),
                    MissingDependencies = String.Join(", ", required.Where(dep =>
                        !Directory.Exists(Path.Combine(root, dep))))
                });
            }
            return list.OrderBy(a => a.Name).ToList();
        }
        private static void CopyDirectory(string from, string to, int depth = 0)
        {
            if (depth > 18) throw new InvalidDataException("Addon has too many nested folders.");
            Directory.CreateDirectory(to);
            foreach (var file in Directory.GetFiles(from))
            {
                var info = new FileInfo(file);
                if ((info.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                File.Copy(file, Path.Combine(to, Path.GetFileName(file)), true);
            }
            foreach (var dir in Directory.GetDirectories(from))
            {
                var info = new DirectoryInfo(dir);
                if ((info.Attributes & FileAttributes.ReparsePoint) != 0 || info.Name == ".git") continue;
                CopyDirectory(dir, Path.Combine(to, info.Name), depth + 1);
            }
        }
        internal static int InstallFolders(string source, string wowExe)
        {
            string root = AddonRoot(wowExe);
            Directory.CreateDirectory(root);
            var dirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var toc in Directory.GetFiles(source, "*.toc", SearchOption.AllDirectories))
            {
                var folder = Path.GetDirectoryName(toc);
                var relative = folder.Substring(source.TrimEnd('\\').Length).TrimStart('\\');
                if (relative.Split('\\').Any(p => p.Equals(".git", StringComparison.OrdinalIgnoreCase))) continue;
                dirs.Add(folder);
            }
            if (dirs.Count == 0) throw new InvalidDataException("No WoW addons (.toc files) found in the selected folder/archive.");
            if (dirs.Count > 150) throw new InvalidDataException("Too many addon folders found; select a smaller pack.");
            int count = 0;
            foreach (var dir in dirs.OrderBy(x => x))
            {
                // WoW requires the addon folder name to match its .toc file name.
                var toc = Directory.GetFiles(dir, "*.toc", SearchOption.TopDirectoryOnly).FirstOrDefault();
                if (toc == null) continue;
                string name = Path.GetFileNameWithoutExtension(toc);
                if (!Regex.IsMatch(name, @"^[a-zA-Z0-9_. -]{1,100}$") ||
                    name == "." || name == "..")
                    throw new InvalidDataException("Unsafe addon name: " + name);
                string destination = Path.Combine(root, name);
                string pending = Path.Combine(root, ".crew-pending-" + Guid.NewGuid().ToString("N"));
                string backup = null;
                try
                {
                    CopyDirectory(dir, pending);
                    if (Directory.Exists(destination))
                    {
                        string backups = Path.Combine(root, ".crew-backups");
                        Directory.CreateDirectory(backups);
                        backup = Path.Combine(backups, name + "-" + DateTime.UtcNow.ToString("yyyyMMddHHmmss") +
                            "-" + Guid.NewGuid().ToString("N").Substring(0, 6));
                        Directory.Move(destination, backup);
                    }
                    Directory.Move(pending, destination);
                    count++;
                }
                catch
                {
                    if (Directory.Exists(pending)) Directory.Delete(pending, true);
                    if (backup != null && Directory.Exists(backup) && !Directory.Exists(destination))
                        Directory.Move(backup, destination);
                    throw;
                }
            }
            return count;
        }
        internal static Task<int> DownloadAndInstallAsync(AddonEntry entry, string wowExe)
        {
            return Task.Run(() =>
            {
                var match = RepoPattern.Match(entry.Url ?? "");
                if (!match.Success)
                    throw new NotSupportedException("This source is not a downloadable GitHub repository. Open its source website instead.");
                string owner = match.Groups[1].Value, repo = match.Groups[2].Value;
                string api = "https://api.github.com/repos/" + owner + "/" + repo;
                string branch;
                using (var web = AddonCatalog.NewClient())
                {
                    var obj = new JavaScriptSerializer().DeserializeObject(web.DownloadString(api))
                        as Dictionary<string, object>;
                    branch = Convert.ToString(obj["default_branch"]);
                }
                if (String.IsNullOrWhiteSpace(branch)) throw new InvalidDataException("No default branch found.");
                string zipUrl = "https://api.github.com/repos/" + owner + "/" + repo + "/zipball/" +
                    Uri.EscapeDataString(branch);
                string zipPath = Path.Combine(Path.GetTempPath(), "crew-addon-" + Guid.NewGuid().ToString("N") + ".zip");
                string extracted = Path.Combine(Path.GetTempPath(), "crew-addon-" + Guid.NewGuid().ToString("N"));
                try
                {
                    DownloadLimited(zipUrl, zipPath, 65L * 1024 * 1024);
                    ExtractLimited(zipPath, extracted, 300L * 1024 * 1024);
                    return InstallFolders(extracted, wowExe);
                }
                finally
                {
                    try { if (File.Exists(zipPath)) File.Delete(zipPath); } catch { }
                    try { if (Directory.Exists(extracted)) Directory.Delete(extracted, true); } catch { }
                }
            });
        }
        private static void DownloadLimited(string url, string file, long maxBytes)
        {
            var request = (HttpWebRequest)WebRequest.Create(url);
            request.UserAgent = "TortoiseCrewAddonHub/1.0";
            request.Timeout = 25000;
            request.ReadWriteTimeout = 25000;
            using (var response = (HttpWebResponse)request.GetResponse())
            using (var input = response.GetResponseStream())
            using (var output = File.Create(file))
            {
                if (response.ContentLength > maxBytes)
                    throw new InvalidDataException("Addon ZIP exceeds download limit.");
                var buffer = new byte[65536];
                long count = 0;
                int length;
                while ((length = input.Read(buffer, 0, buffer.Length)) > 0)
                {
                    count += length;
                    if (count > maxBytes) throw new InvalidDataException("Addon ZIP exceeds download limit.");
                    output.Write(buffer, 0, length);
                }
            }
        }
        private static void ExtractLimited(string file, string target, long maxSize)
        {
            Directory.CreateDirectory(target);
            string root = Path.GetFullPath(target) + Path.DirectorySeparatorChar;
            long total = 0;
            using (var zip = ZipFile.OpenRead(file))
            {
                if (zip.Entries.Count > 3500) throw new InvalidDataException("Too many files in addon archive.");
                foreach (var entry in zip.Entries)
                {
                    int unixMode = (entry.ExternalAttributes >> 16) & 0xF000;
                    if (unixMode == 0xA000) continue; // symlink
                    total += entry.Length;
                    if (total > maxSize) throw new InvalidDataException("Unpacked addon is too large.");
                    string name = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                    string path = Path.GetFullPath(Path.Combine(root, name));
                    if (!path.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidDataException("Unsafe path in addon archive.");
                    if (name.EndsWith("\\") || name.EndsWith("/"))
                    {
                        Directory.CreateDirectory(path);
                        continue;
                    }
                    Directory.CreateDirectory(Path.GetDirectoryName(path));
                    using (var input = entry.Open())
                    using (var output = File.Create(path))
                        input.CopyTo(output);
                }
            }
        }

        internal static Task<int> ImportLocalAsync(string folder, string wowExe, bool includeClientMods)
        {
            return Task.Run(() =>
            {
                string game = GameRoot(wowExe);
                string from = Path.GetFullPath(folder.TrimEnd('\\'));
                if (!Directory.Exists(from)) throw new DirectoryNotFoundException(from);
                if (String.Equals(from, game, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Source and destination must be different game folders.");
                string addonSource = Path.Combine(from, "Interface", "AddOns");
                if (!Directory.Exists(addonSource) &&
                    (Directory.GetFiles(from, "*.toc", SearchOption.TopDirectoryOnly).Length > 0 ||
                     Directory.GetDirectories(from).Any(d => Directory.GetFiles(d, "*.toc", SearchOption.TopDirectoryOnly).Length > 0)))
                    addonSource = from;
                int count = Directory.Exists(addonSource) &&
                    Directory.GetFiles(addonSource, "*.toc", SearchOption.AllDirectories).Length > 0
                    ? InstallFolders(addonSource, wowExe) : 0;
                if (includeClientMods)
                {
                    var extensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                        "nampower.dll", "superwow.dll", "unitxp.dll", "classicapi.dll",
                        "vanillafixes.exe", "dxgi.dll", "d3d9.dll" };
                    string installedDllList = Path.Combine(from, "dlls.txt");
                    if (File.Exists(installedDllList))
                        foreach (string line in File.ReadAllLines(installedDllList))
                        {
                            string name = line.Trim();
                            if (Regex.IsMatch(name, @"^[a-zA-Z0-9_.-]+.dll$", RegexOptions.IgnoreCase))
                                extensions.Add(name);
                        }
                    foreach (var file in Directory.GetFiles(from))
                        if (extensions.Contains(Path.GetFileName(file)) && new FileInfo(file).Length < 50L * 1024 * 1024)
                            BackupAndCopy(file, Path.Combine(game, Path.GetFileName(file)));
                    string fromData = Path.Combine(from, "Data");
                    string toData = Path.Combine(game, "Data");
                    // An extracted pack can contain MPQ files directly, without a WoW/Data directory.
                    var patchDirs = new List<string> { from };
                    if (Directory.Exists(fromData)) patchDirs.Add(fromData);
                    foreach (var patchDir in patchDirs)
                        foreach (var file in Directory.GetFiles(patchDir, "*.mpq"))
                        {
                            string name = Path.GetFileName(file);
                            if (name.StartsWith("patch-", StringComparison.OrdinalIgnoreCase) ||
                                name.IndexOf("comfy", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                name.IndexOf("hd", StringComparison.OrdinalIgnoreCase) >= 0)
                            {
                                Directory.CreateDirectory(toData);
                                BackupAndCopy(file, Path.Combine(toData, name));
                            }
                        }
                    string dlls = Path.Combine(from, "dlls.txt");
                    if (File.Exists(dlls))
                    {
                        string output = Path.Combine(game, "dlls.txt");
                        var lines = File.Exists(output) ? File.ReadAllLines(output).ToList() : new List<string>();
                        foreach (var line in File.ReadAllLines(dlls))
                        {
                            string trimmed = line.Trim();
                            if (Regex.IsMatch(trimmed, @"^[a-zA-Z0-9_.-]+\.dll$", RegexOptions.IgnoreCase) &&
                                File.Exists(Path.Combine(game, trimmed)) &&
                                !lines.Any(l => l.Trim().Equals(trimmed, StringComparison.OrdinalIgnoreCase)))
                                lines.Add(trimmed);
                        }
                        if (File.Exists(output)) File.Copy(output, output + ".crew-backup", true);
                        File.WriteAllLines(output, lines);
                    }
                }
                return count;
            });
        }
        private static void BackupAndCopy(string source, string destination)
        {
            if (File.Exists(destination))
                File.Copy(destination, destination + ".crew-backup", true);
            File.Copy(source, destination, true);
        }
        internal static Task<List<string>> FindClientsAsync(string wowExe)
        {
            return Task.Run(() =>
            {
                var found = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                var queue = new Queue<string>();
                var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                var roots = new List<string> {
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Games"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Games"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Games"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"),
                    @"C:\Games", @"D:\Games", @"C:\OctoWoW", @"C:\Turtle WoW", @"D:\OctoWoW"
                };
                if (!String.IsNullOrWhiteSpace(wowExe) && File.Exists(wowExe))
                {
                    string parent = Path.GetDirectoryName(wowExe);
                    roots.Add(Path.GetDirectoryName(parent));
                }
                foreach (var drive in DriveInfo.GetDrives())
                    try { if (drive.IsReady && drive.DriveType == DriveType.Fixed) roots.Add(drive.RootDirectory.FullName); } catch { }
                foreach (var dir in roots.Where(Directory.Exists)) queue.Enqueue(dir);
                var clock = System.Diagnostics.Stopwatch.StartNew();
                while (queue.Count > 0 && visited.Count < 85000 && clock.Elapsed.TotalSeconds < 35)
                {
                    string dir = queue.Dequeue();
                    if (!visited.Add(dir)) continue;
                    try
                    {
                        if (File.Exists(Path.Combine(dir, "WoW.exe")) &&
                            Directory.Exists(Path.Combine(dir, "Interface", "AddOns")) &&
                            !String.Equals(dir, Path.GetDirectoryName(wowExe), StringComparison.OrdinalIgnoreCase))
                            found.Add(dir);
                        foreach (var next in Directory.EnumerateDirectories(dir))
                        {
                            try
                            {
                                var info = new DirectoryInfo(next);
                                if ((info.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                                if (new[] { "Windows", "$Recycle.Bin", "System Volume Information",
                                    "Program Files", "Program Files (x86)", "AppData", ".git", "node_modules" }
                                    .Any(s => s.Equals(info.Name, StringComparison.OrdinalIgnoreCase))) continue;
                                queue.Enqueue(next);
                            }
                            catch { }
                        }
                    }
                    catch { }
                }
                return found.OrderBy(x => x).ToList();
            });
        }
    }
}
