using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace TortoiseCrew
{
    internal static class AddonRepair
    {
        // Manifest choice must be deterministic and must never select TBC/Wrath
        // merely because its filename happens to be enumerated first.
        internal static string SelectManifest(string folder)
        {
            var files = LongPathFs.GetFiles(folder, "*.toc").ToArray();
            var compatible = files.Where(file => {
                var text = LongPathFs.ReadText(file);
                var m = Regex.Match(text, @"^##\s*Interface\s*:\s*([^\r\n]+)", RegexOptions.Multiline | RegexOptions.IgnoreCase);
                return m.Success && Regex.Matches(m.Groups[1].Value, @"\d+").Cast<Match>()
                    .Any(v => v.Value == "11200" || v.Value == "11800" || v.Value == "11801");
            }).ToList();
            if (compatible.Count == 1) return compatible[0];
            if (compatible.Count == 0 && files.Length == 1 &&
                !Regex.IsMatch(LongPathFs.ReadText(files[0]), @"^##\s*Interface\s*:", RegexOptions.Multiline | RegexOptions.IgnoreCase))
                return files[0]; // Legacy addon with no version declaration.
            throw new InvalidDataException("No unambiguous Vanilla/Turtle addon manifest in " + folder + ". Nothing was imported.");
        }

        internal static void RequireClosed()
        {
            foreach (string name in new[] { "WoW", "VanillaFixes" })
                foreach (var p in Process.GetProcessesByName(name))
                    using (p) { throw new InvalidOperationException("Close WoW before repairing or importing addons."); }
        }

        internal static string Repair(string game)
        {
            RequireClosed();
            game = Path.GetFullPath(game);
            string root = Path.Combine(game, "Interface", "AddOns");
            string config = Path.Combine(game, "WTF", "Config.wtf");
            if (!Directory.Exists(root) || !File.Exists(config))
                throw new InvalidOperationException("This client needs an AddOns folder and WTF/Config.wtf before repair.");
            // Refuse linked roots and children rather than changing another client.
            for (var p = new DirectoryInfo(root); p != null; p = p.Parent)
                if ((p.Attributes & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("Repair does not follow linked client directories.");
            if (LongPathFs.IsReparsePoint(Path.GetDirectoryName(config)) || LongPathFs.IsReparsePoint(config))
                throw new IOException("Repair does not follow linked configuration files.");

            var moves = new List<Tuple<string, string>>();
            var report = new List<string>();
            foreach (string dir in Directory.GetDirectories(root))
            {
                string name = Path.GetFileName(dir);
                if (name.StartsWith(".") || AddonFiles.IsProtectedClientAddon(name)) continue;
                if (LongPathFs.IsReparsePoint(dir)) { report.Add("Skipped linked addon: " + name); continue; }
                if (!LongPathFs.GetFiles(dir, "*.toc").Any()) continue;
                string toc;
                try { toc = SelectManifest(dir); }
                catch (InvalidDataException) { report.Add("Review incompatible/ambiguous addon: " + name); continue; }
                string desired = Path.GetFileNameWithoutExtension(toc);
                if (name.Equals(desired, StringComparison.OrdinalIgnoreCase)) continue;
                if (!AddonFiles.IsSafeAddonName(desired) || AddonFiles.IsProtectedClientAddon(desired))
                { report.Add("Skipped protected/invalid target: " + name); continue; }
                string target = Path.Combine(root, desired);
                if (Directory.Exists(target) || File.Exists(target) || moves.Any(m => m.Item2.Equals(target, StringComparison.OrdinalIgnoreCase)))
                { report.Add("Name conflict; kept both unchanged: " + name + " -> " + desired); continue; }
                moves.Add(Tuple.Create(dir, target));
            }

            string backup = Path.Combine(game, "WTF", "CrewRepair-" + DateTime.UtcNow.ToString("yyyyMMddHHmmss") + "-" + Guid.NewGuid().ToString("N").Substring(0, 8));
            Directory.CreateDirectory(backup);
            File.Copy(config, Path.Combine(backup, "Config.wtf"));
            // Contains paths only, never configuration/password contents.
            File.WriteAllLines(Path.Combine(backup, "renames.txt"), moves.Select(m => m.Item1 + " -> " + m.Item2));
            var done = new List<Tuple<string, string>>();
            try
            {
                RequireClosed();
                foreach (var move in moves)
                {
                    LongPathFs.MoveDirectory(move.Item1, move.Item2);
                    done.Add(move);
                }
                string text = File.ReadAllText(config);
                text = Regex.Replace(text, @"^\s*SET\s+scriptMemory\s+[^\r\n]*(?:\r?\n|$)", "", RegexOptions.Multiline | RegexOptions.IgnoreCase);
                string temporary = Path.Combine(backup, "Config.new");
                File.WriteAllText(temporary, text.TrimEnd('\r', '\n') + "\r\nSET scriptMemory \"0\"\r\n", new UTF8Encoding(false));
                File.Replace(temporary, config, null);
            }
            catch
            {
                foreach (var move in done.AsEnumerable().Reverse()) LongPathFs.MoveDirectory(move.Item2, move.Item1);
                throw;
            }
            foreach (string dir in Directory.GetDirectories(root).Where(d => !Path.GetFileName(d).StartsWith(".")))
                foreach (string toc in Directory.GetFiles(dir, Path.GetFileName(dir) + ".toc"))
                    foreach (string line in File.ReadAllLines(toc))
                    {
                        var m = Regex.Match(line, @"^##\s*(?:Dependencies|RequiredDeps)\s*:\s*(.*)$", RegexOptions.IgnoreCase);
                        if (!m.Success) continue;
                        foreach (string dep in m.Groups[1].Value.Split(',').Select(d => d.Trim()).Where(d => d.Length > 0))
                            if (!AddonFiles.IsSafeAddonName(dep) || !File.Exists(Path.Combine(root, dep, dep + ".toc")))
                                report.Add(Path.GetFileName(dir) + ": missing dependency " + dep);
                    }
            return "Repaired " + done.Count + " addon folder name(s). Script Memory: unlimited.\r\nBackup: " + backup +
                "\r\nProfiles and saved variables preserved.\r\n" + (report.Count == 0 ? "No missing declared dependencies found." : String.Join("\r\n", report));
        }
    }
}
