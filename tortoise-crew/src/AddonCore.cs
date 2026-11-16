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
        public DateTime Updated;
        // No reliable total download count is provided by most GitHub repositories.
        public long? Downloads;
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
        private static DateTime Date(Dictionary<string, object> row, string key)
        {
            DateTime date;
            return DateTime.TryParse(S(row, key), out date) ? date : DateTime.MinValue;
        }
        private static long? DownloadCount(Dictionary<string, object> row)
        {
            long count;
            return long.TryParse(S(row, "downloads"), out count) ? (long?)count : null;
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
                        Stars = Number(row, "stars"),
                        Downloads = DownloadCount(row),
                        Updated = Date(row, "last_commit")
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
                            Downloads = DownloadCount(row),
                            Updated = Date(row, "pushed_at"),
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
                new AddonEntry { Name="Comfy Atmosphere", Description="Inventory local atmosphere/MPQ files for review; client patches are not installed.", Source="Local game patch", IsPack=true },
                new AddonEntry { Name="HD Switch / HD Pack", Description="OctoWoW HD Switch is OctoWoW-realm-only. Import existing HD/MPQ patches cautiously; they may not work on this private realm.", Source="OctoWoW-only / local patch", Url="https://github.com/fmustafayaman/OctoWoW-HD-Switch", IconUrl=Avatar("https://github.com/fmustafayaman/OctoWoW-HD-Switch"), IsPack=true },
                new AddonEntry { Name="Nampower & client DLLs", Description="Inventory local client extensions for compatibility review; no DLLs are installed or enabled.", Source="Local client extension", IsPack=true },
                new AddonEntry { Name="VanillaFixes", Description="Review a local client installation; executable helpers are not copied or launched.", Source="Local client extension", IsPack=true }
            };
        }
    }

    internal sealed class InstalledAddon
    {
        public string Name, Folder, Dependencies, MissingDependencies;
    }

    internal sealed class ImportSummary
    {
        public int Addons;
        public int ClientFiles;
        public int StagedMods;
        public readonly List<string> Warnings = new List<string>();
        public string Describe()
        {
            string result = "Imported " + Addons + " addon(s). " + StagedMods +
                " client mod(s) inventoried for review; no external DLL/MPQ files activated.";
            if (Warnings.Count > 0)
                result += " " + Warnings.Count + " item(s) skipped: " +
                    String.Join("; ", Warnings.Take(3));
            return result;
        }
    }

    internal static class AddonFiles
    {
        private static readonly Regex RepoPattern = new Regex(
            @"^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

        // The Windows 1.18.1 client lives in a deep folder. Staging under
        // Interface\AddOns adds another 60+ characters and used to exceed
        // MAX_PATH even when the final installed addon would fit.
        // Use Win32 extended-length paths for our own file operations.
        // WoW itself is unchanged; paths beyond what the game can read
        // should not be created by the importer.
        internal static string IoPath(string path)
        {
            if (String.IsNullOrWhiteSpace(path))
                throw new ArgumentException("File path cannot be empty.", "path");
            if (path.StartsWith(@"\\?\", StringComparison.Ordinal)) return path;
            string absolute = Path.IsPathRooted(path) ? path : Path.GetFullPath(path);
            if (absolute.Length < 240) return absolute;
            if (absolute.StartsWith(@"\\", StringComparison.Ordinal))
                return @"\\?\UNC\" + absolute.Substring(2);
            return @"\\?\" + absolute;
        }

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

        // Windows forbids path separators and a small set of characters, not valid
        // Vanilla addon prefixes such as !, +, [ or ]. Never treat a toc as a path.
        internal static bool IsSafeAddonName(string name)
        {
            if (String.IsNullOrWhiteSpace(name) || name.Length > 120 ||
                name == "." || name == ".." || name.EndsWith(".") || name.EndsWith(" ") ||
                name.StartsWith(".crew-", StringComparison.OrdinalIgnoreCase) ||
                name.Equals(".git", StringComparison.OrdinalIgnoreCase) ||
                name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 ||
                name.Any(c => Char.IsControl(c) || c == '/' || c == '\\' || c == ':'))
                return false;
            return !Regex.IsMatch(name, @"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$",
                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        }
        // Skip symlink/reparse directories so scans never escape the selected source.
        private static List<string> TocFiles(string source)
        {
            var found = new List<string>();
            var pending = new Queue<Tuple<string, int>>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            pending.Enqueue(Tuple.Create(Path.GetFullPath(source), 0));
            while (pending.Count > 0)
            {
                var item = pending.Dequeue();
                if (item.Item2 > 18 || seen.Count >= 12000)
                    throw new InvalidDataException("Source folder exceeds addon scan limits.");
                if (!seen.Add(item.Item1)) continue;
                try
                {
                    foreach (var file in LongPathFs.GetFiles(item.Item1, "*.toc"))
                        if (!LongPathFs.IsReparsePoint(file))
                            found.Add(file);
                    foreach (var dir in LongPathFs.GetDirectories(item.Item1))
                    {
                        string dirname = Path.GetFileName(dir.TrimEnd('\\', '/'));
                        if (LongPathFs.IsReparsePoint(dir) ||
                            dirname.Equals(".git", StringComparison.OrdinalIgnoreCase) ||
                            dirname.Equals(".crew-backups", StringComparison.OrdinalIgnoreCase) ||
                            dirname.StartsWith(".crew-pending-", StringComparison.OrdinalIgnoreCase))
                            continue;
                        pending.Enqueue(Tuple.Create(dir, item.Item2 + 1));
                    }
                }
                catch (UnauthorizedAccessException ex) { Paths.WriteLog("Skipped inaccessible addon folder: " + ex.Message); }
                catch (IOException ex) { Paths.WriteLog("Skipped unreadable addon folder: " + ex.Message); }
            }
            return found;
        }
        // Built-in UI must come from the verified Turtle client, never another realm.
        internal static bool IsProtectedClientAddon(string name)
        {
            return name.StartsWith("Blizzard_", StringComparison.OrdinalIgnoreCase) ||
                   name.StartsWith("Turtle_", StringComparison.OrdinalIgnoreCase) ||
                   name.Equals("FrameXML", StringComparison.OrdinalIgnoreCase) ||
                   name.Equals("GlueXML", StringComparison.OrdinalIgnoreCase);
        }
        internal static int InstallFoldersInto(string source, string destinationAddons)
        {
            if (!Directory.Exists(source)) throw new DirectoryNotFoundException(source);
            string sourceFull = Path.GetFullPath(source).TrimEnd('\\', '/');
            string destinationFull = Path.GetFullPath(destinationAddons).TrimEnd('\\', '/');
            if (sourceFull.Equals(destinationFull, StringComparison.OrdinalIgnoreCase) ||
                destinationFull.StartsWith(sourceFull + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Destination cannot be inside the source folder.");
            var folders = TocFiles(source).Select(LongPathFs.Parent)
                .Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            if (folders.Count == 0) throw new InvalidDataException("No addon folders containing .toc files found.");
            if (folders.Count > 500) throw new InvalidDataException("Too many addons to import at once (500 maximum).");

            var jobs = new List<Tuple<string, string>>();
            foreach (var folder in folders)
            {
                if (IsProtectedClientAddon(Path.GetFileName(folder))) continue;
                var toc = AddonRepair.SelectManifest(folder);
                var name = Path.GetFileNameWithoutExtension(toc);
                if (!IsSafeAddonName(name))
                    throw new InvalidDataException("Unsupported addon filename: " + name + ". No files were changed.");
                if (IsProtectedClientAddon(name) ||
                    IsProtectedClientAddon(Path.GetFileName(folder)))
                {
                    Paths.WriteLog("Protected built-in UI not imported from external source: " + name);
                    continue;
                }
                jobs.Add(Tuple.Create(folder, name));
            }
            if (jobs.Select(x => x.Item2).Distinct(StringComparer.OrdinalIgnoreCase).Count() != jobs.Count)
                throw new InvalidDataException("Duplicate addon names; no files imported.");
            if (jobs.Count == 0) return 0;

            LongPathFs.EnsureDirectory(destinationFull);
            string transaction = Path.Combine(destinationFull, ".crew-pending-" + Guid.NewGuid().ToString("N"));
            string staged = Path.Combine(transaction, "staged");
            LongPathFs.EnsureDirectory(staged);
            var ordered = jobs.OrderBy(j => j.Item2, StringComparer.OrdinalIgnoreCase).ToList();
            try
            {
                // Stage all files before changing even one installed addon.
                foreach (var job in ordered)
                    CopyDirectory(job.Item1, Path.Combine(staged, job.Item2));

                string backups = Path.Combine(destinationFull, ".crew-backups");
                LongPathFs.EnsureDirectory(backups);
                var changed = new List<Tuple<string, string>>();
                try
                {
                    foreach (var job in ordered)
                    {
                        string destination = Path.Combine(destinationFull, job.Item2);
                        string original = null;
                        if (LongPathFs.DirectoryExists(destination))
                        {
                            original = Path.Combine(backups, job.Item2 + "-" +
                                DateTime.UtcNow.ToString("yyyyMMddHHmmss") + "-" +
                                Guid.NewGuid().ToString("N").Substring(0, 8));
                            LongPathFs.MoveDirectory(destination, original);
                        }
                        changed.Add(Tuple.Create(destination, original));
                        LongPathFs.MoveDirectory(Path.Combine(staged, job.Item2), destination);
                    }
                    return changed.Count;
                }
                catch
                {
                    foreach (var item in changed.AsEnumerable().Reverse())
                    {
                        if (LongPathFs.DirectoryExists(item.Item1))
                            LongPathFs.DeleteDirectory(item.Item1);
                        if (item.Item2 != null && LongPathFs.DirectoryExists(item.Item2))
                            LongPathFs.MoveDirectory(item.Item2, item.Item1);
                    }
                    throw;
                }
            }
            finally
            {
                if (LongPathFs.DirectoryExists(transaction))
                    LongPathFs.DeleteDirectory(transaction);
            }
        }
        private static void CopyDirectory(string from, string to, int depth = 0)
        {
            if (depth > 18) throw new InvalidDataException("Addon has too many nested folders.");
            LongPathFs.EnsureDirectory(to);
            foreach (var file in LongPathFs.GetFiles(from))
            {
                if (LongPathFs.IsReparsePoint(file)) continue;
                string fileName = Path.GetFileName(file);
                // Never treat executable payloads inside an addon as WoW UI files.
                string extension = Path.GetExtension(fileName);
                if (new[] { ".exe", ".dll", ".asi", ".mpq", ".bat", ".cmd",
                    ".ps1", ".vbs", ".js", ".msi", ".com", ".scr" }
                    .Any(x => x.Equals(extension, StringComparison.OrdinalIgnoreCase)))
                {
                    Paths.WriteLog("Skipped executable inside addon: " + fileName);
                    continue;
                }
                LongPathFs.Copy(file, Path.Combine(to, fileName));
            }
            foreach (var dir in LongPathFs.GetDirectories(from))
            {
                string dirName = Path.GetFileName(dir.TrimEnd('\\', '/'));
                if (LongPathFs.IsReparsePoint(dir) ||
                    dirName.Equals(".git", StringComparison.OrdinalIgnoreCase)) continue;
                CopyDirectory(dir, Path.Combine(to, dirName), depth + 1);
            }
        }
        internal static int InstallFolders(string source, string wowExe)
        {
            return InstallFoldersInto(source, AddonRoot(wowExe));
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

        internal static Task<ImportSummary> ImportLocalDetailedAsync(
            string folder, string wowExe, bool includeClientMods)
        {
            return Task.Run(() => ImportLocalInto(folder, GameRoot(wowExe), includeClientMods));
        }
        internal static Task<int> ImportLocalAsync(string folder, string wowExe, bool includeClientMods)
        {
            return Task.Run(() => ImportLocalInto(folder, GameRoot(wowExe), includeClientMods).Addons);
        }
        // Separable destination argument makes file operations testable with a
        // throwaway directory, without requiring the real verified WoW.exe.
        internal static ImportSummary ImportLocalInto(string folder, string gameRoot, bool includeClientMods)
        {
            string from = Path.GetFullPath(folder).TrimEnd('\\', '/');
            string game = Path.GetFullPath(gameRoot).TrimEnd('\\', '/');
            if (!Directory.Exists(from)) throw new DirectoryNotFoundException(from);
            if (!Directory.Exists(game)) throw new DirectoryNotFoundException(game);
            if (from.Equals(game, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Select a DIFFERENT game folder as the import source.");
            if (game.StartsWith(from + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("The target WoW client is inside the source folder.");
            var result = new ImportSummary();

            string addonSource = Path.Combine(from, "Interface", "AddOns");
            if (!Directory.Exists(addonSource)) addonSource = from;
            if (TocFiles(addonSource).Count > 0)
                result.Addons = InstallFoldersInto(addonSource, Path.Combine(game, "Interface", "AddOns"));

            // Matching client build numbers do not establish DLL/MPQ compatibility.
            // Scan always imports ordinary addons, and inventories client mods for
            // review instead of copying binaries into the currently working game.
            if (includeClientMods)
                InventoryClientMods(from, game, result);
            return result;
        }

        private static void InventoryClientMods(string source, string game, ImportSummary result)
        {
            var lines = new List<string> {
                "# Client modifications awaiting compatibility verification",
                "Original client: " + source,
                "Target client: " + game,
                "No MPQ, DLL, DXVK wrapper or executable was installed or enabled.",
                "These files require independent client-specific testing before activation.",
                ""
            };
            string[] roots = { source, Path.Combine(source, "Data") };
            foreach (string root in roots.Where(Directory.Exists))
            {
                foreach (string file in Directory.EnumerateFiles(root))
                {
                    var info = new FileInfo(file);
                    if ((info.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                    string name = info.Name;
                    bool clientMod = name.Equals("dlls.txt", StringComparison.OrdinalIgnoreCase) ||
                        name.Equals("VanillaFixes.exe", StringComparison.OrdinalIgnoreCase) ||
                        name.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) ||
                        name.EndsWith(".asi", StringComparison.OrdinalIgnoreCase) ||
                        (name.EndsWith(".mpq", StringComparison.OrdinalIgnoreCase) &&
                         (name.StartsWith("patch-", StringComparison.OrdinalIgnoreCase) ||
                          name.IndexOf("hd", StringComparison.OrdinalIgnoreCase) >= 0 ||
                          name.IndexOf("comfy", StringComparison.OrdinalIgnoreCase) >= 0));
                    if (!clientMod) continue;
                    result.StagedMods++;
                    lines.Add(file + " | bytes=" + info.Length);
                }
            }
            if (result.StagedMods == 0) return;
            try
            {
                // Inventory outside WoW.exe's directory. No multi-GB duplicate archives.
                string parent = Path.GetDirectoryName(game);
                string review = Path.Combine(parent, "_Crew_Mod_Review");
                Directory.CreateDirectory(review);
                string output = Path.Combine(review, "review-" +
                    DateTime.UtcNow.ToString("yyyyMMddHHmmss") + "-" +
                    Guid.NewGuid().ToString("N").Substring(0, 8) + ".txt");
                File.WriteAllLines(output, lines);
                result.Warnings.Add(result.StagedMods + " client mod(s) require compatibility review: " + output);
            }
            catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException)
            {
                result.Warnings.Add("Could not write client-mod review: " + ex.Message);
            }
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
                            (Directory.Exists(Path.Combine(dir, "Interface", "AddOns")) || Directory.Exists(Path.Combine(dir, "Data"))) &&
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
