using System;
using System.Diagnostics;
using System.IO;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace TortoiseCrew
{
    internal static class PasswordVault
    {
        private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("TortoiseCrew/DPAPI/v1");
        private static string FileFor(string username)
        {
            if (!Regex.IsMatch(username ?? "", "^(MICHAEL|JAYKE|BERNARD|AUGUST)$"))
                throw new ArgumentException("Invalid account.");
            return Path.Combine(Paths.Root, "credential-" + username + ".bin");
        }

        public static string Read(string username)
        {
            try
            {
                var file = FileFor(username);
                if (!File.Exists(file)) return "";
                byte[] encrypted = File.ReadAllBytes(file);
                byte[] plain = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
                string result = Encoding.UTF8.GetString(plain);
                Array.Clear(plain, 0, plain.Length);
                return result;
            }
            catch (Exception ex)
            {
                Paths.WriteLog("Protected password read failed: " + ex.GetType().Name);
                return "";
            }
        }

        public static void Save(string username, string password)
        {
            if (!CrewEnrollment.ValidExistingPassword(password))
                throw new ArgumentException("Password must use letters and digits (1-16 characters).");
            Directory.CreateDirectory(Paths.Root);
            byte[] raw = Encoding.UTF8.GetBytes(password);
            try
            {
                byte[] encrypted = ProtectedData.Protect(raw, Entropy, DataProtectionScope.CurrentUser);
                string path = FileFor(username);
                File.WriteAllBytes(path, encrypted);
                TryRestrictToCurrentWindowsUser(path);
            }
            finally { Array.Clear(raw, 0, raw.Length); }
        }

        internal static void TryRestrictToCurrentWindowsUser(string file)
        {
            try
            {
                var current = WindowsIdentity.GetCurrent().User;
                var acl = new FileSecurity();
                acl.SetAccessRuleProtection(true, false);
                acl.AddAccessRule(new FileSystemAccessRule(current, FileSystemRights.FullControl, AccessControlType.Allow));
                File.SetAccessControl(file, acl);
            }
            catch (Exception ex)
            {
                Paths.WriteLog("File ACL warning: " + ex.GetType().Name);
            }
        }
    }

    public sealed class CrewReply
    {
        public bool ok { get; set; }
        public string code { get; set; }
    }

    internal static class CrewEnrollment
    {
        private const string BootstrapPrivateBase64 = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNBSkdFVVl3YjJBQnFGRzJQSHF2QTVWamdTWDNkaVBvdFVNZUlRS2N5dFdBUUFBQUpodWdwUEdib0tUCnhnQUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQUpHRVVZd2IyQUJxRkcyUEhxdkE1VmpnU1gzZGlQb3RVTWVJUUtjeXRXQVEKQUFBRUNsbEt1Z2lmV1kvS3hMck9zTHhidlhQSkEwTThVTEVkMEpXcW9nN0czZ2dBa1lSUmpCdllBR29VYlk4ZXE4RGxXTwpCSmZkMkkraTFReDRoQXB6SzFZQkFBQUFGR055WlhjdFpXNXliMnd0WW05dmRITjBjbUZ3QVE9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K";
        private static string BootstrapFile { get { return Path.Combine(Paths.Root, "crew-bootstrap"); } }

        public static bool ValidExistingPassword(string pass)
        {
            return !String.IsNullOrEmpty(pass) && Regex.IsMatch(pass, "^[A-Za-z0-9]{1,16}$");
        }

        public static bool ValidNewPassword(string pass)
        {
            return !String.IsNullOrEmpty(pass) &&
                Regex.IsMatch(pass, "^[A-Za-z0-9]{12,16}$") &&
                Regex.IsMatch(pass, "[A-Za-z]") && Regex.IsMatch(pass, "[0-9]");
        }

        private static void EnsureBootstrapFile()
        {
            Directory.CreateDirectory(Paths.Root);
            string key = Encoding.UTF8.GetString(Convert.FromBase64String(BootstrapPrivateBase64));
            if (!key.Contains("BEGIN OPENSSH PRIVATE KEY"))
                throw new InvalidDataException("Bundled onboarding key is invalid.");
            if (!File.Exists(BootstrapFile) || File.ReadAllText(BootstrapFile) != key)
            {
                File.WriteAllText(BootstrapFile, key, new UTF8Encoding(false));
                PasswordVault.TryRestrictToCurrentWindowsUser(BootstrapFile);
            }
        }

        public static async Task<CrewReply> SendAsync(
            LauncherSettings settings, string action, string username, string currentPassword,
            string newPassword, string invite)
        {
            if (!Regex.IsMatch(username ?? "", "^(MICHAEL|JAYKE|BERNARD|AUGUST)$"))
                return new CrewReply { ok = false, code = "INVALID_ACCOUNT" };
            if (action != "register" && action != "pair" && action != "change-password")
                return new CrewReply { ok = false, code = "INVALID_ACTION" };

            string keyPath;
            if (action == "change-password")
                keyPath = SshSupport.ExistingOrNewKey(settings);
            else
            {
                EnsureBootstrapFile();
                keyPath = BootstrapFile;
            }
            string publicKey = action == "change-password" ? "" : SshSupport.PublicKey(settings);
            object request;
            if (action == "register")
                request = new { action, username, invite, password = newPassword, publicKey };
            else if (action == "pair")
                request = new { action, username, password = currentPassword, publicKey };
            else
                request = new { action, username, currentPassword, password = newPassword };

            // Only credentials and the SSH public key travel over the authenticated,
            // encrypted SSH channel. Passwords never appear in CLI args or launcher logs.
            string payload = new JavaScriptSerializer().Serialize(request);
            return await Task.Run(() =>
            {
                try
                {
                    if (!Regex.IsMatch(settings.Host ?? "", "^[a-z0-9.-]+$", RegexOptions.IgnoreCase) ||
                        settings.SshPort < 1 || settings.SshPort > 65535)
                        return new CrewReply { ok = false, code = "SERVER_SETTINGS_INVALID" };

                    string args = "-T -F NUL -o BatchMode=yes -o IdentitiesOnly=yes " +
                        "-o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 " +
                        "-o ClearAllForwardings=yes -o RequestTTY=no " +
                        "-i \"" + keyPath + "\" -p " + settings.SshPort + " root@" + settings.Host;
                    var psi = new ProcessStartInfo(SshSupport.SshPath, args)
                    {
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        WindowStyle = ProcessWindowStyle.Hidden,
                        RedirectStandardInput = true,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true
                    };
                    using (var proc = Process.Start(psi))
                    {
                        if (proc == null) return new CrewReply { ok = false, code = "SSH_UNAVAILABLE" };
                        proc.StandardInput.Write(payload);
                        proc.StandardInput.Close();
                        if (!proc.WaitForExit(14000))
                        {
                            proc.Kill();
                            return new CrewReply { ok = false, code = "ONBOARDING_TIMEOUT" };
                        }
                        string output = proc.StandardOutput.ReadToEnd().Trim();
                        if (output.Length > 3000)
                            return new CrewReply { ok = false, code = "BAD_SERVER_RESPONSE" };
                        try
                        {
                            var response = new JavaScriptSerializer().Deserialize<CrewReply>(output);
                            if (response != null && Regex.IsMatch(response.code ?? "", "^[A-Z_]+$"))
                                return response;
                        }
                        catch { }
                        return new CrewReply { ok = false, code = "ONBOARDING_CONNECTION_FAILED" };
                    }
                }
                catch (Exception ex)
                {
                    Paths.WriteLog("Crew enrollment failed (no passwords logged): " + ex.GetType().Name);
                    return new CrewReply { ok = false, code = "ONBOARDING_UNAVAILABLE" };
                }
            });
        }
    }
}
