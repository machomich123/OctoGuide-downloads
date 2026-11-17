import { execFileSync } from 'node:child_process';
import { ACCOUNTS } from './config.mjs';

// ClassicAPI source: Security::CredStore::Save stores UTF-8 bytes as a generic
// Windows Credential at ClassicAPI/WoW/<realmlist>/<account>. The password is
// encrypted and access-controlled by Windows. We use the verified same format
// after successful Crew authentication, so the first launch can be native.
const SAVE = [
  'Add-Type -TypeDefinition @"',
  'using System;',
  'using System.Runtime.InteropServices;',
  'public static class CrewNativeVault {',
  ' [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]',
  ' public struct Cred {',
  '  public uint Flags; public uint Type;',
  '  [MarshalAs(UnmanagedType.LPWStr)] public string TargetName;',
  '  [MarshalAs(UnmanagedType.LPWStr)] public string Comment;',
  '  public long LastWritten;',
  '  public uint CredentialBlobSize; public IntPtr CredentialBlob;',
  '  public uint Persist; public uint AttributeCount;',
  '  public IntPtr Attributes;',
  '  [MarshalAs(UnmanagedType.LPWStr)] public string TargetAlias;',
  '  [MarshalAs(UnmanagedType.LPWStr)] public string UserName;',
  ' }',
  ' [DllImport("advapi32.dll", EntryPoint="CredWriteW", CharSet=CharSet.Unicode, SetLastError=true)]',
  ' public static extern bool Write(ref Cred value, uint flags);',
  '}',
  '"@',
  '$ErrorActionPreference="Stop"',
  '$data = [Console]::In.ReadToEnd() | ConvertFrom-Json',
  '$account = [string]$data.account',
  '$realm = [string]$data.realm',
  'if ($realm -ne "127.0.0.1" -or $account -notmatch "^[A-Z][A-Z0-9_]{0,15}$") { exit 12 }',
  '$bytes = [Convert]::FromBase64String([string]$data.value)',
  'if ($bytes.Length -lt 1 -or $bytes.Length -gt 16) { exit 13 }',
  '$target = "ClassicAPI/WoW/" + $realm + "/" + $account',
  '$native = [Runtime.InteropServices.Marshal]::AllocHGlobal($bytes.Length)',
  'try {',
  ' [Runtime.InteropServices.Marshal]::Copy($bytes,0,$native,$bytes.Length)',
  ' $entry = New-Object CrewNativeVault+Cred',
  ' $entry.Type = 1; $entry.TargetName = $target',
  ' $entry.CredentialBlob = $native',
  ' $entry.CredentialBlobSize = [uint32]$bytes.Length',
  ' $entry.Persist = 2; $entry.UserName = $target',
  ' if (-not [CrewNativeVault]::Write([ref]$entry,0)) { exit 14 }',
  ' [Console]::Out.Write("CLASSICAPI_VAULT_READY")',
  '} finally {',
  ' for($i=0;$i -lt $bytes.Length;$i++){',
  '  [Runtime.InteropServices.Marshal]::WriteByte($native,$i,0)',
  ' }',
  ' [Runtime.InteropServices.Marshal]::FreeHGlobal($native)',
  ' [Array]::Clear($bytes,0,$bytes.Length)',
  '}',
].join('\n');

export function nativeVaultScript() { return SAVE; }

export function saveNativeCredential(account, password, realm = '127.0.0.1') {
  if (process.platform !== 'win32' || !ACCOUNTS.includes(account) ||
      realm !== '127.0.0.1' || typeof password !== 'string' ||
      !/^[\x20-\x7e]{1,16}$/.test(password)) {
    throw new Error('Invalid ClassicAPI credential request.');
  }
  const input = JSON.stringify({
    realm, account, value: Buffer.from(password, 'utf8').toString('base64'),
  });
  const result = execFileSync('powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command', SAVE], {
      input, encoding: 'utf8', timeout: 10000,
      windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 16 * 1024,
    }).trim();
  if (result !== 'CLASSICAPI_VAULT_READY')
    throw new Error('Windows did not confirm the secure ClassicAPI credential.');
  return { ready: true };
}
