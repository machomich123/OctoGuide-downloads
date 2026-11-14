using System;
using System.IO;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;

namespace TortoiseCrew
{
    // Passwords are never sent to or stored in the launcher repository, nor
    // provided to Altare's gateway. Only the currently logged-in Windows user
    // can decrypt the DPAPI-protected password stored on this PC.
    internal static class PasswordVault
    {
        private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("TortoiseCrew/DPAPI/v1");

        private static string FileFor(string username)
        {
            if (!Regex.IsMatch(username ?? "", "^(MICHAEL|JAYKE|BERNARD|AUGUST)$"))
                throw new ArgumentException("Invalid game account.");
            return Path.Combine(Paths.Root, "credential-" + username + ".bin");
        }

        public static string Read(string username)
        {
            try
            {
                string file = FileFor(username);
                if (!File.Exists(file))
                    return "";
                byte[] encrypted = File.ReadAllBytes(file);
                byte[] plain = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
                try
                {
                    return Encoding.UTF8.GetString(plain);
                }
                finally
                {
                    Array.Clear(plain, 0, plain.Length);
                }
            }
            catch (Exception ex)
            {
                Paths.WriteLog("Protected password read unavailable: " + ex.GetType().Name);
                return "";
            }
        }

        public static void Save(string username, string password)
        {
            if (!CrewEnrollment.ValidExistingPassword(password))
                throw new ArgumentException("The WoW client supports 1 to 16 printable characters.");
            Directory.CreateDirectory(Paths.Root);
            byte[] raw = Encoding.UTF8.GetBytes(password);
            try
            {
                byte[] encrypted = ProtectedData.Protect(raw, Entropy, DataProtectionScope.CurrentUser);
                string file = FileFor(username);
                File.WriteAllBytes(file, encrypted);
                TryRestrictToCurrentWindowsUser(file);
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
                acl.AddAccessRule(new FileSystemAccessRule(
                    current, FileSystemRights.FullControl, AccessControlType.Allow));
                File.SetAccessControl(file, acl);
            }
            catch (Exception ex)
            {
                Paths.WriteLog("Credential ACL check: " + ex.GetType().Name);
            }
        }
    }

    internal static class CrewEnrollment
    {
        // Auto registration is intentionally NOT included. Altare's public SSH
        // gateway ignored authorized_keys forced-command restrictions in live tests.
        public static bool ValidExistingPassword(string pass)
        {
            // Vanilla-era game protocol accepts 1–16 printable characters.
            // No forced numbers, uppercase letters, or special-character rules.
            return !String.IsNullOrWhiteSpace(pass) &&
                pass.Length <= 16 &&
                Regex.IsMatch(pass, @"^[\x20-\x7e]{1,16}$");
        }

        public static bool ValidNewPassword(string pass)
        {
            return ValidExistingPassword(pass);
        }
    }
}
