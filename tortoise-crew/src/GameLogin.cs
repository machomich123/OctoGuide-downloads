using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;

namespace TortoiseCrew
{
    // Ordinary process startup: no injected DLL, loader, or password delivery.
    internal static class GameLogin
    {
        internal static ProcessStartInfo StartInfo(string path)
        {
            return new ProcessStartInfo(path) {
                WorkingDirectory = Path.GetDirectoryName(path), UseShellExecute = false
            };
        }
        internal static Task<Process> StartAsync(LauncherSettings settings)
        {
            if (!GameDetector.IsVerified(settings.WowPath))
                throw new InvalidOperationException("Select a verified WoW.exe before playing.");
            var game = Process.Start(StartInfo(settings.WowPath));
            if (game == null) throw new InvalidOperationException("Windows did not start WoW.exe.");
            return Task.FromResult(game);
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
