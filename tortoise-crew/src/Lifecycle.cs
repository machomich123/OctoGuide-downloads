using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace TortoiseCrew
{
    // The launcher may exit immediately after starting WoW; this independent, windowless
    // process keeps the SSH child alive and closes it only when the game process exits.
    internal static class SessionMonitor
    {
        private const string MutexName = @"Local\TortoiseCrewGameSession";

        internal static bool IsSessionActive()
        {
            try
            {
                using (var mutex = Mutex.OpenExisting(MutexName))
                {
                    bool available;
                    try { available = mutex.WaitOne(0); }
                    catch (AbandonedMutexException) { available = true; }
                    if (available)
                    {
                        mutex.ReleaseMutex();
                        return false;
                    }
                    return true;
                }
            }
            catch (WaitHandleCannotBeOpenedException) { return false; }
        }

        internal static async Task<bool> HandOffAsync(int wowPid, int sshPid)
        {
            string marker = Path.Combine(Paths.Root, "session-" + Guid.NewGuid().ToString("N") + ".ready");
            var args = "--watch " + wowPid + " " + sshPid + " " + Path.GetFileNameWithoutExtension(marker).Substring(8);
            var start = new ProcessStartInfo(Paths.Executable, args)
            {
                WorkingDirectory = Paths.Root,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            using (var monitor = Process.Start(start))
            {
                if (monitor == null) return false;
                for (int attempt = 0; attempt < 40; attempt++)
                {
                    if (File.Exists(marker))
                    {
                        try { File.Delete(marker); } catch { }
                        Paths.WriteLog("Game session monitor confirmed; SSH tunnel ownership handed off.");
                        return true;
                    }
                    if (monitor.HasExited)
                        return false;
                    await Task.Delay(50);
                }
                return false;
            }
        }

        internal static void Watch(int wowPid, int sshPid, string handoffId)
        {
            if (wowPid <= 0 || sshPid <= 0 ||
                !Regex.IsMatch(handoffId ?? "", "^[0-9a-f]{32}$"))
                throw new InvalidOperationException("Invalid background session arguments.");

            string marker = Path.Combine(Paths.Root, "session-" + handoffId + ".ready");
            using (var game = Process.GetProcessById(wowPid))
            using (var ssh = Process.GetProcessById(sshPid))
            using (var singleSession = new Mutex(false, MutexName))
            {
                if (!String.Equals(game.ProcessName, "WoW", StringComparison.OrdinalIgnoreCase) ||
                    !String.Equals(ssh.ProcessName, "ssh", StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Unexpected process identity in game session.");
                if (!singleSession.WaitOne(0))
                    throw new InvalidOperationException("An SSH game session is already active.");

                try
                {
                    File.WriteAllText(marker, "active");
                    Paths.WriteLog("Session monitor attached to WoW process " + wowPid + " and SSH " + sshPid);
                    game.WaitForExit();
                }
                finally
                {
                    try
                    {
                        // Reuse the original process handle, not a newly looked-up PID.
                        if (!ssh.HasExited) ssh.Kill();
                    }
                    catch (Exception ex) { Paths.WriteLog("SSH cleanup: " + ex.GetType().Name); }
                    try { File.Delete(marker); } catch { }
                    Paths.WriteLog("WoW exited; game tunnel was shut down.");
                    singleSession.ReleaseMutex();
                }
            }
        }
    }

    // The helper verifies trust before replacing anything, waits for the old UI,
    // and serializes installation with both other helpers and desktop launches.
    internal static class SafeUpdater
    {
        internal static void ReplaceInstalled(string requestedTarget, string expectedHash, int parentPid = 0)
        {
            string target = Path.GetFullPath(requestedTarget);
            string running = Path.GetFullPath(Assembly.GetExecutingAssembly().Location);
            string source = Path.GetFullPath(Path.Combine(Paths.Root, "pending-update.exe"));
            if (!String.Equals(target, Paths.Executable, StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(running, source, StringComparison.OrdinalIgnoreCase) ||
                !Regex.IsMatch(expectedHash ?? "", "^[0-9a-fA-F]{64}$") ||
                !String.Equals(GameDetector.HashOf(running), expectedHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Refusing an unverified or unexpected update.");
            ReleaseTrust.RequireTrusted(running);
            if (SessionMonitor.IsSessionActive())
                throw new InvalidOperationException("Close WoW before updating the launcher.");

            if (parentPid > 0)
            {
                Process parent = null;
                try { parent = Process.GetProcessById(parentPid); }
                catch (ArgumentException) { } // The old UI already exited.
                if (parent != null)
                {
                    using (parent)
                    {
                        if (!String.Equals(parent.MainModule.FileName, target, StringComparison.OrdinalIgnoreCase))
                            throw new InvalidOperationException("Unexpected update parent process.");
                        if (!parent.WaitForExit(20000))
                            throw new IOException("The old launcher is still running. Close it before updating.");
                    }
                }
            }

            string staged = Path.Combine(Paths.Root, "update-ready-" + Guid.NewGuid().ToString("N") + ".exe");
            string backup = Path.Combine(Paths.Root, "launcher-previous.exe");
            using (var updateMutex = new Mutex(false, @"Local\TortoiseCrewUpdater"))
            {
                bool acquired;
                try { acquired = updateMutex.WaitOne(0); }
                catch (AbandonedMutexException) { acquired = true; }
                if (!acquired) throw new InvalidOperationException("Another launcher update is already running.");
                try
                {
                    using (var instance = LauncherInstance.Acquire(20000))
                    {
                        if (instance == null)
                            throw new IOException("The launcher is still open. Close it before updating.");
                        File.Copy(running, staged, false);
                        if (!String.Equals(GameDetector.HashOf(staged), expectedHash, StringComparison.OrdinalIgnoreCase))
                            throw new InvalidDataException("Staged update failed the SHA-256 check.");
                        ReleaseTrust.RequireTrusted(staged);
                        ReplaceWhenClosed(staged, target, backup);
                        if (!String.Equals(GameDetector.HashOf(target), expectedHash, StringComparison.OrdinalIgnoreCase))
                        {
                            if (File.Exists(backup)) File.Copy(backup, target, true);
                            throw new InvalidDataException("Installed update checksum mismatch.");
                        }
                    }
                    // The new UI must be able to acquire its mutex before we wait for it.
                    string startupId = Guid.NewGuid().ToString("N");
                    string readyMarker = Path.Combine(Paths.Root, "update-started-" + startupId + ".ready");
                    try
                    {
                        using (var launched = Process.Start(new ProcessStartInfo(target, "--updated " + startupId) {
                            WorkingDirectory = Paths.Root, UseShellExecute = true }))
                        {
                            if (launched == null) throw new IOException("Windows did not start the updated launcher.");
                            bool ready = false;
                            for (int attempt = 0; attempt < 100; attempt++)
                            {
                                if (launched.HasExited) break;
                                if (File.Exists(readyMarker)) { ready = true; break; }
                                Thread.Sleep(100);
                            }
                            if (!ready)
                                throw new IOException("The updated launcher did not open a window. No success was recorded.");
                        }
                    }
                    catch (Exception error)
                    {
                        Paths.WriteLog("Updated launcher startup failed: " + error.Message);
                        // Do not overwrite a still-running new process. Keep the backup
                        // for recovery; never hide policy failures behind a retry loop.
                        using (var instance = LauncherInstance.Acquire(0))
                        {
                            if (instance != null && File.Exists(backup))
                            {
                                try
                                {
                                    using (File.Open(target, FileMode.Open, FileAccess.ReadWrite, FileShare.None)) { }
                                    File.Copy(backup, target, true);
                                    Paths.WriteLog("Previous launcher restored; manual restart is required.");
                                }
                                catch (IOException restoreError) { Paths.WriteLog("Backup retained: " + restoreError.Message); }
                            }
                        }
                        throw new InvalidOperationException("The update could not open. The previous version or its backup was kept. " +
                            error.Message, error);
                    }
                    finally
                    {
                        try { if (File.Exists(readyMarker)) File.Delete(readyMarker); } catch { }
                    }
                    Paths.WriteLog("Launcher update opened successfully: " + expectedHash);
                }
                finally
                {
                    try { if (File.Exists(staged)) File.Delete(staged); } catch { }
                    updateMutex.ReleaseMutex();
                }
            }
        }

        private static void ReplaceWhenClosed(string staged, string target, string backup)
        {
            Exception lastError = null;
            for (int attempt = 0; attempt < 80; attempt++)
            {
                try
                {
                    if (File.Exists(target))
                    {
                        // File.Replace alone may succeed while an EXE is mapped by an
                        // old process. Require exclusive access before the atomic swap.
                        using (File.Open(target, FileMode.Open, FileAccess.ReadWrite, FileShare.None)) { }
                        File.Replace(staged, target, backup, true);
                    }
                    else File.Move(staged, target);
                    return;
                }
                catch (IOException ex) { lastError = ex; }
                catch (UnauthorizedAccessException ex) { lastError = ex; }
                Thread.Sleep(200);
            }
            throw new IOException("The old launcher has not released its program file. The current version was kept.", lastError);
        }
    }
}
