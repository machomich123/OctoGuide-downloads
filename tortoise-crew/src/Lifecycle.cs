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

    // A standalone update helper, invoked from the hash-verified downloaded EXE.
    // Only a verified binary in the app's own folder is allowed to replace the installed
    // launcher. File.Replace keeps the previous version as a recoverable backup.
    internal static class SafeUpdater
    {
        internal static void ReplaceInstalled(string requestedTarget, string expectedHash)
        {
            string target = Path.GetFullPath(requestedTarget);
            string running = Path.GetFullPath(Assembly.GetExecutingAssembly().Location);
            string source = Path.GetFullPath(Path.Combine(Paths.Root, "pending-update.exe"));

            if (!String.Equals(target, Paths.Executable, StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(running, source, StringComparison.OrdinalIgnoreCase) ||
                !Regex.IsMatch(expectedHash ?? "", "^[0-9a-fA-F]{64}$") ||
                !String.Equals(GameDetector.HashOf(running), expectedHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Refusing an unverified or unexpected update.");

            if (SessionMonitor.IsSessionActive())
                throw new InvalidOperationException("Close WoW before updating the launcher.");

            Directory.CreateDirectory(Paths.Root);
            string staged = Path.Combine(Paths.Root, "update-ready-" + Guid.NewGuid().ToString("N") + ".exe");
            string backup = Path.Combine(Paths.Root, "launcher-previous.exe");
            File.Copy(running, staged, false);
            if (!String.Equals(GameDetector.HashOf(staged), expectedHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Staged update failed the SHA-256 check.");

            // Update helper and launcher must never start separate concurrent swaps.
            using (var updateMutex = new Mutex(false, @"Local\TortoiseCrewUpdater"))
            {
                if (!updateMutex.WaitOne(0))
                    throw new InvalidOperationException("Another launcher update is already running.");
                try
                {
                    Exception lastError = null;
                    for (int i = 0; i < 80; i++)
                    {
                        try
                        {
                            if (File.Exists(target))
                            {
                                // NTFS atomic replacement, preserving last working EXE.
                                File.Replace(staged, target, backup, true);
                            }
                            else
                                File.Move(staged, target);

                            if (!String.Equals(GameDetector.HashOf(target), expectedHash,
                                                StringComparison.OrdinalIgnoreCase))
                            {
                                if (File.Exists(backup)) File.Copy(backup, target, true);
                                throw new InvalidDataException("Installed update checksum mismatch.");
                            }
                            try
                            {
                                Process.Start(new ProcessStartInfo(target)
                                {
                                    WorkingDirectory = Paths.Root,
                                    UseShellExecute = true
                                });
                            }
                            catch (Exception startError)
                            {
                                // A fully downloaded binary can still be unable to launch.
                                // Restore the previous working version from the atomic backup.
                                Paths.WriteLog("Updated launcher failed to start; restoring backup: " +
                                               startError.GetType().Name);
                                if (File.Exists(backup))
                                {
                                    File.Copy(backup, target, true);
                                    try
                                    {
                                        Process.Start(new ProcessStartInfo(target)
                                        {
                                            WorkingDirectory = Paths.Root,
                                            UseShellExecute = true
                                        });
                                    }
                                    catch (Exception rollbackError)
                                    {
                                        Paths.WriteLog("Backup relaunch failed: " + rollbackError.GetType().Name);
                                    }
                                }
                                throw new InvalidOperationException("Update could not launch. Previous version was restored.", startError);
                            }
                            Paths.WriteLog("Launcher update installed successfully: " + expectedHash);
                            return;
                        }
                        catch (IOException ex)
                        {
                            lastError = ex;
                            Thread.Sleep(200);
                        }
                        catch (UnauthorizedAccessException ex)
                        {
                            lastError = ex;
                            Thread.Sleep(200);
                        }
                    }
                    throw new IOException("Could not replace the launcher after the previous instance closed.",
                                          lastError);
                }
                finally
                {
                    try { if (File.Exists(staged)) File.Delete(staged); } catch { }
                    updateMutex.ReleaseMutex();
                }
            }
        }
    }
}
