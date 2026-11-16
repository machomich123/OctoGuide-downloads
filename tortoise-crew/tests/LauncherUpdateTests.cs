using System;
using System.IO;
using System.Reflection;
using System.Threading;

namespace TortoiseCrew
{
    internal static class LauncherUpdateTests
    {
        private static void Check(bool value, string message)
        {
            if (!value) throw new Exception("TEST FAILED: " + message);
            Console.WriteLine("PASS: " + message);
        }

        public static int Main(string[] args)
        {
            try
            {
                Check(Paths.Version == Assembly.GetExecutingAssembly().GetName().Version.ToString(3),
                    "UI/update version follows compiled assembly");
                Check(Paths.Version == "1.0.12", "release candidate is 1.0.12");
                Check(!RemoteUpdates.IsNewer(new RealmManifest { LauncherVersion = "1.0.12" }),
                    "same version does not repeat update");
                Check(!RemoteUpdates.IsNewer(new RealmManifest { LauncherVersion = "1.0.12.0" }),
                    "three-part and four-part versions compare equally");
                Check(!RemoteUpdates.IsNewer(new RealmManifest { LauncherVersion = "1.0.8" }),
                    "older version does not downgrade");
                Check(RemoteUpdates.IsNewer(new RealmManifest { LauncherVersion = "1.0.13" }),
                    "newer version is detected");
                Check(!RemoteUpdates.IsNewer(new RealmManifest { LauncherVersion = "1.0.13", UpdatesPaused = true }),
                    "paused release is never offered");
                Check(!RemoteUpdates.IsNewer(null) &&
                    !RemoteUpdates.IsNewer(new RealmManifest { LauncherVersion = "invalid" }),
                    "invalid release information cannot trigger update");

                string testMutex = @"Local\TortoiseCrewUiTest-" + Guid.NewGuid().ToString("N");
                bool secondBlocked = false;
                using (var first = LauncherInstance.Acquire(0, testMutex))
                {
                    Check(first != null, "first desktop launch acquires UI ownership");
                    var worker = new Thread(() => {
                        using (var second = LauncherInstance.Acquire(100, testMutex)) secondBlocked = second == null;
                    });
                    worker.Start();
                    worker.Join();
                    Check(secondBlocked, "concurrent desktop launch cannot overwrite running launcher");
                }
                bool acquiredAfterClose = false;
                var retry = new Thread(() => {
                    using (var instance = LauncherInstance.Acquire(100, testMutex)) acquiredAfterClose = instance != null;
                });
                retry.Start();
                retry.Join();
                Check(acquiredAfterClose, "closing UI releases ownership for updater");

                bool rejected = false;
                try { ReleaseTrust.RequireTrusted(Assembly.GetExecutingAssembly().Location); }
                catch (InvalidDataException) { rejected = true; }
                Check(rejected, "strict signed-release validation rejects unsigned artifact");
                rejected = false;
                try { ReleaseTrust.ValidateForLaunch(Assembly.GetExecutingAssembly().Location); }
                catch (InvalidDataException) { rejected = true; }
                Check(rejected, "unsigned update rejected before Windows execution attempt");

                // Validate the native structure layout with a Windows-signed PE,
                // then corrupt its hashed content to prove digest verification.
                if (args.Length != 1) throw new ArgumentException("Pass a PE with an embedded Authenticode signature.");
                string signed = args[0];
                ReleaseTrust.RequireTrusted(signed);
                ReleaseTrust.ValidateForLaunch(signed);
                Console.WriteLine("PASS: valid Windows publisher signature accepted");
                string tampered = Path.Combine(Path.GetTempPath(), "crew-signature-test-" + Guid.NewGuid().ToString("N") + ".exe");
                try
                {
                    byte[] bytes = File.ReadAllBytes(signed);
                    bytes[1024] ^= 1;
                    File.WriteAllBytes(tampered, bytes);
                    rejected = false;
                    try { ReleaseTrust.RequireTrusted(tampered); }
                    catch (InvalidDataException) { rejected = true; }
                    Check(rejected, "modified signed executable rejected");
                    rejected = false;
                    try { ReleaseTrust.ValidateForLaunch(tampered); }
                    catch (InvalidDataException) { rejected = true; }
                    Check(rejected, "invalid signature is not treated as an unsigned build");
                }
                finally { if (File.Exists(tampered)) File.Delete(tampered); }
                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex);
                return 1;
            }
        }
    }
}
