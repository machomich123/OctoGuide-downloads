using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.Text;

namespace TortoiseCrew
{
    // Win32 file operations bypass the legacy .NET Framework MAX_PATH checks.
    // All paths come from known addon roots and must remain on the local machine.
    // No global registry, long-path policy, or administrator changes are needed.
    internal static class LongPathFs
    {
        private const uint INVALID_ATTRIBUTES = 0xffffffff;
        private const uint FILE_ATTRIBUTE_DIRECTORY = 0x10;
        private const uint FILE_ATTRIBUTE_REPARSE_POINT = 0x400;
        private const uint FILE_ATTRIBUTE_READONLY = 0x1;
        private const uint GENERIC_WRITE = 0x40000000;
        private const uint CREATE_ALWAYS = 2;
        private const uint FILE_ATTRIBUTE_NORMAL = 0x80;
        private static readonly IntPtr InvalidFindHandle = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct FindData
        {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
            public uint SizeHigh;
            public uint SizeLow;
            public uint Reserved0;
            public uint Reserved1;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            public string Name;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)]
            public string AlternateName;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetFileAttributesW", SetLastError = true)]
        private static extern uint GetAttributes(string path);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "SetFileAttributesW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetAttributes(string path, uint attributes);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "CreateDirectoryW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateDir(string path, IntPtr security);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "RemoveDirectoryW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool RemoveDir(string path);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "DeleteFileW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DeleteFile(string path);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "CopyFileW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CopyFile(string source, string target, bool failIfExists);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "MoveFileW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool MoveFile(string source, string target);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "FindFirstFileW", SetLastError = true)]
        private static extern IntPtr FindFirstFile(string path, out FindData data);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "FindNextFileW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FindNextFile(IntPtr handle, out FindData data);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FindClose(IntPtr handle);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "CreateFileW", SetLastError = true)]
        private static extern SafeFileHandle CreateFileHandle(
            string path, uint desiredAccess, uint shareMode, IntPtr security,
            uint creationDisposition, uint attributes, IntPtr templateFile);

        private static IOException Error(string verb, string path)
        {
            int code = Marshal.GetLastWin32Error();
            return new IOException(verb + ": " + path + " (" +
                new Win32Exception(code).Message + ", Win32 " + code + ")");
        }

        internal static string NativePath(string path)
        {
            if (String.IsNullOrEmpty(path)) throw new ArgumentException("Empty path.");
            if (path.StartsWith(@"\\?\", StringComparison.Ordinal)) return path;
            string absolute = Path.IsPathRooted(path) ? path : Path.GetFullPath(path);
            if (absolute.StartsWith(@"\\", StringComparison.Ordinal))
                return @"\\?\UNC\" + absolute.Substring(2);
            return @"\\?\" + absolute;
        }

        internal static bool DirectoryExists(string path)
        {
            uint attr = GetAttributes(NativePath(path));
            return attr != INVALID_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY) != 0;
        }

        internal static bool FileExists(string path)
        {
            uint attr = GetAttributes(NativePath(path));
            return attr != INVALID_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY) == 0;
        }

        internal static bool IsReparsePoint(string path)
        {
            uint attr = GetAttributes(NativePath(path));
            if (attr == INVALID_ATTRIBUTES) throw Error("Read attributes failed", path);
            return (attr & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
        }

        // Path.GetDirectoryName itself applies MAX_PATH in .NET Framework 4.x,
        // even when only parsing a string. Extract the parent without invoking it.
        internal static string Parent(string path)
        {
            string trimmed = path.TrimEnd('\\', '/');
            int separator = Math.Max(trimmed.LastIndexOf('\\'), trimmed.LastIndexOf('/'));
            if (separator < 0) return null;
            if (separator == 2 && trimmed.Length >= 3 && trimmed[1] == ':')
                return trimmed.Substring(0, 3);
            return trimmed.Substring(0, separator);
        }

        internal static void EnsureDirectory(string path)
        {
            if (DirectoryExists(path)) return;
            string parent = Parent(path);
            if (String.IsNullOrEmpty(parent) || parent == path)
                throw new IOException("Invalid directory: " + path);
            EnsureDirectory(parent);
            if (!CreateDir(NativePath(path), IntPtr.Zero) && !DirectoryExists(path))
                throw Error("Create directory failed", path);
        }

        private static IEnumerable<Tuple<string, uint>> Entries(string directory, string pattern)
        {
            if (!DirectoryExists(directory)) throw new DirectoryNotFoundException(directory);
            FindData data;
            IntPtr handle = FindFirstFile(NativePath(Path.Combine(directory, pattern)), out data);
            if (handle == InvalidFindHandle)
            {
                int code = Marshal.GetLastWin32Error();
                if (code == 2 || code == 18) yield break;
                throw new IOException("Directory scan failed: " + directory + " (Win32 " + code + ")");
            }
            try
            {
                do
                {
                    if (data.Name == "." || data.Name == "..") continue;
                    yield return Tuple.Create(Path.Combine(directory, data.Name), data.Attributes);
                } while (FindNextFile(handle, out data));
                int error = Marshal.GetLastWin32Error();
                if (error != 18) throw new IOException("Directory enumeration failed: " + directory + " (Win32 " + error + ")");
            }
            finally { FindClose(handle); }
        }

        internal static IEnumerable<string> GetFiles(string directory, string pattern = "*")
        {
            return Entries(directory, pattern).Where(item =>
                (item.Item2 & FILE_ATTRIBUTE_DIRECTORY) == 0).Select(item => item.Item1).ToList();
        }

        internal static IEnumerable<string> GetDirectories(string directory)
        {
            return Entries(directory, "*").Where(item =>
                (item.Item2 & FILE_ATTRIBUTE_DIRECTORY) != 0).Select(item => item.Item1).ToList();
        }

        internal static void Copy(string source, string target)
        {
            if (!CopyFile(NativePath(source), NativePath(target), true))
                throw Error("Copy failed", target);
        }

        internal static void MoveDirectory(string source, string target)
        {
            if (!MoveFile(NativePath(source), NativePath(target)))
                throw Error("Move failed", source + " -> " + target);
        }

        internal static void DeleteDirectory(string directory)
        {
            if (!DirectoryExists(directory)) return;
            foreach (var item in Entries(directory, "*"))
            {
                if ((item.Item2 & FILE_ATTRIBUTE_DIRECTORY) != 0)
                {
                    if ((item.Item2 & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
                    {
                        if (!RemoveDir(NativePath(item.Item1)))
                            throw Error("Remove junction failed", item.Item1);
                    }
                    else DeleteDirectory(item.Item1);
                }
                else
                {
                    if ((item.Item2 & FILE_ATTRIBUTE_READONLY) != 0 &&
                        !SetAttributes(NativePath(item.Item1), item.Item2 & ~FILE_ATTRIBUTE_READONLY))
                        throw Error("Clear read-only failed", item.Item1);
                    if (!DeleteFile(NativePath(item.Item1)))
                        throw Error("Delete failed", item.Item1);
                }
            }
            if (!RemoveDir(NativePath(directory)))
                throw Error("Remove directory failed", directory);
        }

        internal static string ReadText(string path)
        {
            using (var handle = CreateFileHandle(NativePath(path), 0x80000000, 1,
                IntPtr.Zero, 3, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero))
            {
                if (handle.IsInvalid) throw Error("Read manifest failed", path);
                using (var stream = new FileStream(handle, FileAccess.Read))
                using (var reader = new StreamReader(stream, Encoding.UTF8, true))
                    return reader.ReadToEnd();
            }
        }

        // Only used by the offline test fixture; production import reads user files.
        internal static void WriteText(string path, string content)
        {
            using (var handle = CreateFileHandle(NativePath(path), GENERIC_WRITE, 0,
                IntPtr.Zero, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero))
            {
                if (handle.IsInvalid) throw Error("Write fixture failed", path);
                using (var stream = new FileStream(handle, FileAccess.Write))
                using (var writer = new StreamWriter(stream, new UTF8Encoding(false)))
                    writer.Write(content);
            }
        }
    }
}
