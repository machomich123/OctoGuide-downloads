using System;
using System.IO;
using System.Runtime.InteropServices;

namespace TortoiseCrew
{
    // Verify the PE digest and the publisher's chain with Windows, not just the
    // presence of a certificate. This never installs certificates or changes policy.
    internal static class ReleaseTrust
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct FileInfo
        {
            public uint Size;
            [MarshalAs(UnmanagedType.LPWStr)] public string Path;
            public IntPtr File;
            public IntPtr Subject;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct TrustData
        {
            public uint Size;
            public IntPtr PolicyCallback, SipClient;
            public uint UiChoice, RevocationChecks, UnionChoice;
            public IntPtr FileInfo;
            public uint StateAction;
            public IntPtr StateData, Url;
            public uint ProviderFlags, UiContext;
            public IntPtr SignatureSettings;
        }

        [DllImport("wintrust.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
        private static extern int WinVerifyTrust(IntPtr window, ref Guid action, ref TrustData data);

        internal static void RequireTrusted(string path)
        {
            Verify(path, true);
        }

        // A checksum and CI startup are not evidence of publisher trust on the
        // user's PC. Reject unsigned updates before attempting to execute them.
        internal static void ValidateForLaunch(string path)
        {
            Verify(path, true);
        }

        private static void Verify(string path, bool requireSignature)
        {
            if (!System.IO.File.Exists(path)) throw new FileNotFoundException("Update file is missing.", path);
            var file = new FileInfo { Size = (uint)Marshal.SizeOf(typeof(FileInfo)), Path = path };
            IntPtr pointer = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(FileInfo)));
            var action = new Guid("00AAC56B-CD44-11D0-8CC2-00C04FC295EE");
            var data = new TrustData {
                Size = (uint)Marshal.SizeOf(typeof(TrustData)), UiChoice = 2,
                RevocationChecks = 1, UnionChoice = 1, FileInfo = pointer,
                StateAction = 1, ProviderFlags = 0x80
            };
            try
            {
                Marshal.StructureToPtr(file, pointer, false);
                int result = WinVerifyTrust(new IntPtr(-1), ref action, ref data);
                if (!requireSignature && result == unchecked((int)0x800B0100)) return;
                if (result != 0)
                    throw new InvalidDataException("This update has no valid Windows-trusted publisher signature " +
                        "(0x" + unchecked((uint)result).ToString("X8") + "). " +
                        "The current launcher has been kept. Windows protection has not been changed.");
            }
            finally
            {
                data.StateAction = 2;
                WinVerifyTrust(new IntPtr(-1), ref action, ref data);
                Marshal.DestroyStructure(pointer, typeof(FileInfo));
                Marshal.FreeHGlobal(pointer);
            }
        }
    }
}
