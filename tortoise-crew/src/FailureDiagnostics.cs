using System;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;

namespace TortoiseCrew
{
    internal enum FailureStage { AccountConnection, RelayConnection, GameStartup, GameExit, LaunchSession }
    internal static class FailureDiagnostics
    {
        private static readonly object Gate = new object();
        internal static string Record(FailureStage stage, Exception error, int? exitCode = null)
        { return Write(Path.Combine(Paths.Root, "diagnostics"), stage, error, exitCode); }

        // Allowlisted values only: no exception messages, credentials, URLs or packet content.
        internal static string Write(string directory, FailureStage stage, Exception error, int? exitCode = null)
        {
            try
            {
                lock (Gate)
                {
                    Directory.CreateDirectory(directory);
                    var win32 = error as Win32Exception;
                    string path = Path.Combine(directory, "failure-" + DateTime.UtcNow.ToString("yyyyMMddTHHmmssfffZ") + "-" + Guid.NewGuid().ToString("N") + ".json");
                    string json = new JavaScriptSerializer().Serialize(new {
                        utc = DateTime.UtcNow.ToString("o"), launcherVersion = Paths.Version,
                        stage = stage.ToString(), category = Category(error, exitCode),
                        hresult = error == null ? (int?)null : error.HResult,
                        windowsCode = win32 == null ? (int?)null : win32.NativeErrorCode,
                        gameExitCode = exitCode
                    });
                    File.WriteAllText(path, json, new UTF8Encoding(false));
                    foreach (var old in new DirectoryInfo(directory).GetFiles("failure-*.json")
                        .OrderByDescending(f => f.LastWriteTimeUtc).ThenByDescending(f => f.Name).Skip(20))
                        try { old.Delete(); } catch { }
                    return path;
                }
            }
            catch { return null; }
        }
        internal static string Category(Exception error, int? exitCode = null)
        {
            var win32 = error as Win32Exception;
            if (win32 != null && (win32.NativeErrorCode == 577 || win32.NativeErrorCode == 1260)) return "WindowsApplicationControl";
            if (error is UnauthorizedAccessException || (win32 != null && win32.NativeErrorCode == 5)) return "AccessDenied";
            if (exitCode.HasValue && exitCode.Value != 0) return "GameExitedWithError";
            if (error is System.Net.WebSockets.WebSocketException || error is System.Net.Http.HttpRequestException || error is System.Net.Sockets.SocketException) return "ConnectionFailure";
            if (error is TimeoutException) return "Timeout";
            return "OperationFailed";
        }
        internal static string UserMessage(Exception error, string report)
        {
            string category = Category(error);
            string message = category == "WindowsApplicationControl" ? "Windows Application Control blocked the program. Windows protections were left unchanged."
                : category == "AccessDenied" ? "Windows denied access while starting the game or connection."
                : "The game or connection could not start. See the failure report for the affected step.";
            return message + (report == null ? "\n\nThe failure report could not be saved." : "\n\nFailure report: " + report);
        }
    }
}
