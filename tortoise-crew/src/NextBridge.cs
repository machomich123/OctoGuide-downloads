using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace TortoiseCrew
{
    // The existing 1.0.11 updater only understands a replacement EXE. This
    // version is a bridge into an isolated Node application, not a policy bypass.
    // Never change Windows trust settings or remove the previous launcher here.
    internal static class NextBridge
    {
        private const string ResourceName = "CrewNextBundle";
        private const string RuntimeVersion = "v26.13.1";
        private const string RuntimeArchive = "node-v26.13.1-win-x64.zip";
        private const string RuntimeArchiveSha256 =
            "E2EDDA75BFB089654705CF65A13B58933BFD5F57148E8EBDA916F58A2474F1F7";
        private const string RuntimeExeSha256 =
            "F5109DC868EC38703AD8F305E0ACEECE717CB60D4889873F434017AF4E96CCCB";

        internal static bool TestEmbeddedBundle()
        {
            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName))
            {
                if (stream == null) throw new InvalidDataException("Launcher migration bundle was not embedded.");
                using (var zip = new ZipArchive(stream, ZipArchiveMode.Read, false))
                {
                    bool main = false, installer = false, ui = false;
                    foreach (var entry in zip.Entries)
                    {
                        string item = entry.FullName.Replace('\\', '/');
                        if (item == "src/main.mjs") main = true;
                        if (item == "src/migrate.mjs") installer = true;
                        if (item == "public/index.html") ui = true;
                    }
                    if (!main || !installer || !ui) throw new InvalidDataException("Migration resources are incomplete.");
                }
            }
            return true;
        }

        internal static async Task MigrateAfterUpdateAsync(Form originalLauncher)
        {
            try
            {
                if (!TestEmbeddedBundle()) throw new InvalidDataException("The new launcher bundle is missing.");
                await Task.Run(() => PerformMigration());
                if (!originalLauncher.IsDisposed)
                {
                    Paths.WriteLog("Node launcher migration reported success; switching desktop shortcut.");
                    originalLauncher.Close();
                }
            }
            catch (Exception error)
            {
                Paths.WriteLog("Node migration deferred: " + error.GetType().Name + ": " + error.Message);
                if (!originalLauncher.IsDisposed)
                {
                    MessageBox.Show(originalLauncher,
                        "The new launcher could not finish installing. Your current launcher and account files " +
                        "were kept unchanged. You can keep using the old launcher.\n\n" + error.Message,
                        "Tortoise Crew migration", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }
        }

        private static void PerformMigration()
        {
            if (SessionMonitor.IsSessionActive())
                throw new InvalidOperationException("Close WoW before migrating the launcher.");
            string root = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TortoiseCrewNext");
            Directory.CreateDirectory(root);
            string candidate = Path.Combine(root, "bootstrap-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(candidate);
            try
            {
                ExtractBundle(candidate);
                string runtime = SelectNodeRuntime(root);
                var info = new ProcessStartInfo(runtime, "\"" + Path.Combine(candidate, "src", "migrate.mjs") + "\" --apply")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    WorkingDirectory = candidate
                };
                using (var process = Process.Start(info))
                {
                    if (process == null) throw new IOException("Cannot launch the migration process.");
                    Task<string> stdout = process.StandardOutput.ReadToEndAsync();
                    Task<string> stderr = process.StandardError.ReadToEndAsync();
                    if (!process.WaitForExit(60000))
                    {
                        process.Kill();
                        throw new IOException("New launcher did not acknowledge startup.");
                    }
                    string output = stdout.GetAwaiter().GetResult();
                    string errors = stderr.GetAwaiter().GetResult();
                    if (process.ExitCode != 0)
                        throw new IOException("Migration stopped: " +
                            (String.IsNullOrWhiteSpace(errors) ? "the new UI did not open." :
                            errors.Substring(0, Math.Min(750, errors.Length))));
                    if (output.IndexOf("\"migrated\": true", StringComparison.OrdinalIgnoreCase) < 0)
                        throw new InvalidDataException("The new launcher did not confirm its installation.");
                }
            }
            finally
            {
                try { Directory.Delete(candidate, true); }
                catch (IOException) { Paths.WriteLog("Bootstrap staging cleanup deferred."); }
            }
        }

        private static void ExtractBundle(string output)
        {
            using (Stream raw = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName))
            {
                if (raw == null) throw new InvalidDataException("Missing embedded launcher source.");
                using (var zip = new ZipArchive(raw, ZipArchiveMode.Read, false))
                {
                    if (zip.Entries.Count > 100) throw new InvalidDataException("Unexpected bundle entry count.");
                    long total = 0;
                    string fullOutput = Path.GetFullPath(output) + Path.DirectorySeparatorChar;
                    foreach (ZipArchiveEntry entry in zip.Entries)
                    {
                        string path = entry.FullName.Replace('/', '\\');
                        if (String.IsNullOrWhiteSpace(path) || path.StartsWith("\\") ||
                            path.Contains("..") || path.IndexOf(':') >= 0 ||
                            path.EndsWith("\\", StringComparison.Ordinal))
                            continue; // Do not extract directories or unsafe names.
                        total += entry.Length;
                        if (total > 5 * 1024 * 1024)
                            throw new InvalidDataException("Embedded bundle exceeds size limit.");
                        string destination = Path.GetFullPath(Path.Combine(output, path));
                        if (!destination.StartsWith(fullOutput, StringComparison.OrdinalIgnoreCase))
                            throw new InvalidDataException("Unsafe embedded bundle path.");
                        string extension = Path.GetExtension(destination).ToLowerInvariant();
                        if (extension != ".mjs" && extension != ".js" && extension != ".json" &&
                            extension != ".html" && extension != ".css")
                            throw new InvalidDataException("Unexpected bundled file type.");
                        Directory.CreateDirectory(Path.GetDirectoryName(destination));
                        entry.ExtractToFile(destination, false);
                    }
                }
            }
            if (!File.Exists(Path.Combine(output, "src", "main.mjs")) ||
                !File.Exists(Path.Combine(output, "src", "migrate.mjs")))
                throw new InvalidDataException("The new launcher bundle is incomplete.");
        }

        private static string SelectNodeRuntime(string root)
        {
            string installed = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "nodejs", "node.exe");
            if (TrustedRuntime(installed)) return installed;

            string runtimeDir = Path.Combine(root, "runtime");
            string runtime = Path.Combine(runtimeDir, "node.exe");
            if (File.Exists(runtime) &&
                String.Equals(GameDetector.HashOf(runtime), RuntimeExeSha256, StringComparison.OrdinalIgnoreCase) &&
                TrustedRuntime(runtime)) return runtime;

            // Official runtime is signed by OpenJS Foundation. Fetch only a fixed
            // upstream archive and verify its known SHA-256 and executable digest.
            string archive = Path.Combine(root, "node-download-" + Guid.NewGuid().ToString("N") + ".zip");
            try
            {
                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                var request = (HttpWebRequest)WebRequest.Create(
                    "https://nodejs.org/dist/" + RuntimeVersion + "/" + RuntimeArchive);
                request.Timeout = 35000;
                request.ReadWriteTimeout = 35000;
                using (var response = request.GetResponse())
                using (var from = response.GetResponseStream())
                using (var to = File.Create(archive))
                {
                    byte[] buffer = new byte[65536];
                    long total = 0;
                    int n;
                    while ((n = from.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        total += n;
                        if (total > 75 * 1024 * 1024)
                            throw new InvalidDataException("Official Node runtime download is unexpectedly large.");
                        to.Write(buffer, 0, n);
                    }
                }
                if (!String.Equals(GameDetector.HashOf(archive), RuntimeArchiveSha256,
                    StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("Official Node runtime ZIP checksum mismatch.");
                Directory.CreateDirectory(runtimeDir);
                using (var zip = ZipFile.OpenRead(archive))
                {
                    var entry = zip.GetEntry("node-v26.13.1-win-x64/node.exe");
                    if (entry == null) throw new InvalidDataException("Official Node runtime executable not found.");
                    string staged = Path.Combine(runtimeDir, "node-candidate.exe");
                    entry.ExtractToFile(staged, true);
                    if (!String.Equals(GameDetector.HashOf(staged), RuntimeExeSha256,
                        StringComparison.OrdinalIgnoreCase) || !TrustedRuntime(staged))
                        throw new InvalidDataException("Official Node executable is not trusted.");
                    File.Copy(staged, runtime, true);
                    File.Delete(staged);
                }
                return runtime;
            }
            finally
            {
                if (File.Exists(archive)) File.Delete(archive);
            }
        }

        private static bool TrustedRuntime(string executable)
        {
            try
            {
                if (!File.Exists(executable)) return false;
                ReleaseTrust.RequireTrusted(executable);
                using (var process = Process.Start(new ProcessStartInfo(executable, "--version")
                {
                    UseShellExecute = false, RedirectStandardOutput = true,
                    CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden
                }))
                {
                    if (process == null || !process.WaitForExit(5000))
                    {
                        if (process != null) process.Kill();
                        return false;
                    }
                    return process.ExitCode == 0 &&
                        process.StandardOutput.ReadToEnd().Trim().StartsWith("v26.", StringComparison.Ordinal);
                }
            }
            catch { return false; }
        }
    }
}
