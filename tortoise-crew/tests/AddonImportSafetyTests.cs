using System;
using System.IO;
using System.Linq;

namespace TortoiseCrew
{
    // Offline smoke tests: run against temporary throwaway game directories only.
    internal static class AddonImportSafetyTests
    {
        private static void Check(bool condition, string message)
        {
            if (!condition) throw new Exception("TEST FAILED: " + message);
        }
        private static void Addon(string source, string name, string marker)
        {
            string dir = Path.Combine(source, "Interface", "AddOns", name);
            LongPathFs.EnsureDirectory(dir);
            LongPathFs.WriteText(Path.Combine(dir, name + ".toc"), "## Interface: 11801\n" + name + ".lua\n");
            LongPathFs.WriteText(Path.Combine(dir, name + ".lua"), marker);
        }
        public static int Main()
        {
            string tmp = Path.Combine(Path.GetTempPath(), "crew-import-tests-" + Guid.NewGuid().ToString("N"));
            try
            {
                string source = Path.Combine(tmp, "client-octo");
                string target = Path.Combine(tmp, "client-turtle");
                string dest = Path.Combine(target, "Interface", "AddOns");
                Directory.CreateDirectory(dest);
                Addon(source, "CommunityA", "new-a");
                Addon(source, "CommunityB", "new-b");
                Addon(source, "Blizzard_TalentUI", "BROKEN CORE");
                Addon(source, "Turtle_GroupUI", "BROKEN TURTLE CORE");
                Addon(target, "Blizzard_TalentUI", "trusted-core");
                Addon(target, "Turtle_GroupUI", "trusted-turtle");
                Addon(target, "CommunityA", "old-a");
                string sourceAddons = Path.Combine(source, "Interface", "AddOns");
                string unsafeDll = Path.Combine(sourceAddons, "CommunityA", "evil.dll");
                File.WriteAllText(unsafeDll, "unsafe");

                int count = AddonFiles.InstallFoldersInto(sourceAddons, dest);
                Check(count == 2, "Only two community addons imported");
                Check(File.ReadAllText(Path.Combine(dest, "CommunityA", "CommunityA.lua")) == "new-a",
                    "CommunityA imported");
                Check(File.ReadAllText(Path.Combine(dest, "Blizzard_TalentUI", "Blizzard_TalentUI.lua")) ==
                    "trusted-core", "Blizzard core kept intact");
                Check(File.ReadAllText(Path.Combine(dest, "Turtle_GroupUI", "Turtle_GroupUI.lua")) ==
                    "trusted-turtle", "Turtle core kept intact");
                Check(!File.Exists(Path.Combine(dest, "CommunityA", "evil.dll")),
                    "Executable payload inside addon skipped");
                Check(Directory.EnumerateDirectories(Path.Combine(dest, ".crew-backups"),
                    "CommunityA-*").Any(), "Previous community addon version backed up");
                Console.WriteLine("PASS: import, rollback backup, protected core, binary filtering");

                // A broken later source folder must not replace already installed addons.
                Addon(source, "CommunityC", "new-c");
                string locked = Path.Combine(sourceAddons, "CommunityC", "locked.lua");
                File.WriteAllText(locked, "locked");
                bool failed = false;
                using (var hold = new FileStream(locked, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
                {
                    try { AddonFiles.InstallFoldersInto(sourceAddons, dest); }
                    catch (IOException) { failed = true; }
                }
                Check(failed, "Locked file aborts staging");
                Check(!Directory.Exists(Path.Combine(dest, "CommunityC")),
                    "Partially staged addon not installed");
                Check(File.ReadAllText(Path.Combine(dest, "CommunityA", "CommunityA.lua")) == "new-a",
                    "Installed addon unchanged after staging failure");
                Console.WriteLine("PASS: staging failure preserves installed addons");

                // DLLs and foreign MPQs are recorded outside active target, never enabled.
                Directory.CreateDirectory(Path.Combine(source, "Data"));
                File.WriteAllText(Path.Combine(source, "nampower.dll"), "foreign-dll");
                File.WriteAllText(Path.Combine(source, "Data", "patch-O.mpq"), "foreign-mpq");
                var summary = AddonFiles.ImportLocalInto(source, target, true);
                Check(summary.Addons == 3, "All three community addons imported");
                Check(summary.StagedMods >= 2, "Foreign mods inventoried");
                Check(!File.Exists(Path.Combine(target, "nampower.dll")), "Foreign DLL not activated");
                Check(!File.Exists(Path.Combine(target, "Data", "patch-O.mpq")), "Foreign MPQ not activated");
                Check(Directory.Exists(Path.Combine(tmp, "_Crew_Mod_Review")),
                    "Mod review inventory saved outside target client");
                Console.WriteLine("PASS: mods inventoried without activating foreign binaries");

                // Regression: a deeply nested target creates a temporary staging
                // path over MAX_PATH (260 chars), while its installed files are short.
                string longTarget = Path.Combine(tmp, "target-" + new string('x', 85));
                string longDest = Path.Combine(longTarget, "Interface", "AddOns");
                LongPathFs.EnsureDirectory(longDest);
                Check(Path.Combine(longDest, ".crew-pending-" + new string('a', 32),
                    "staged", "CommunityA", "CommunityA.lua").Length > 260,
                    "Test must actually exceed classic Windows MAX_PATH");
                int firstLong = AddonFiles.InstallFoldersInto(sourceAddons, longDest);
                Check(firstLong == 3, "Long staging path can import community addons");
                Check(LongPathFs.FileExists(Path.Combine(longDest,
                    "CommunityA", "CommunityA.lua")), "Long-path staging commits files");
                int secondLong = AddonFiles.InstallFoldersInto(sourceAddons, longDest);
                Check(secondLong == 3, "Repeated import with long backup paths works");
                Check(LongPathFs.GetDirectories(Path.Combine(longDest, ".crew-backups"))
                    .Any(x => Path.GetFileName(x).StartsWith("CommunityA-", StringComparison.OrdinalIgnoreCase)),
                    "Long-path backup created");
                Console.WriteLine("PASS: long staging and repeated backup paths");

                // Regression: .toc discovery must traverse a long source path.
                string nested = Path.Combine(sourceAddons, "Nested",
                    new string('a', 70), new string('b', 70), new string('c', 70), "DeepAddon");
                LongPathFs.EnsureDirectory(nested);
                string deepToc = Path.Combine(nested, "DeepAddon.toc");
                Check(deepToc.Length > 260, "Long source fixture must exceed MAX_PATH");
                LongPathFs.WriteText(deepToc, "## Interface: 11801\nDeepAddon.lua\n");
                LongPathFs.WriteText(Path.Combine(nested, "DeepAddon.lua"), "deep-content");
                int deepCount = AddonFiles.InstallFoldersInto(sourceAddons, dest);
                Check(deepCount == 4, "Long source path discovered and imported");
                Check(File.ReadAllText(Path.Combine(dest, "DeepAddon", "DeepAddon.lua"))
                    == "deep-content", "Deep source content copied");
                Console.WriteLine("PASS: long source discovery and copy");
                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex.ToString());
                return 1;
            }
            finally
            {
                try { if (Directory.Exists(tmp)) Directory.Delete(tmp, true); }
                catch { }
            }
        }
    }
}
