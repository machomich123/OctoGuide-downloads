import { spawn } from 'node:child_process';
import path from 'node:path';
import { ACCOUNTS } from './config.mjs';

// Automate the login UI using the OS input APIs, like password managers.
// No game patch, new executable, DLL injection, or plaintext config entries.
// The password goes ONLY to the Windows helper's stdin (never to argv/logs).
const SCRIPT = [
  '$ErrorActionPreference = "Stop"',
  'Add-Type -AssemblyName System.Windows.Forms',
  'Add-Type -TypeDefinition @"',
  'using System;',
  'using System.Runtime.InteropServices;',
  'public static class CrewFocus {',
  '  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();',
  '  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);',
  '  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);',
  '  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);',
  '  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int show);',
  '  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);',
  '  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);',
  '  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint from, uint to, bool attach);',
  '  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();',
  '  public static bool Activate(IntPtr window) {',
  '    if (window == IntPtr.Zero || !IsWindowVisible(window)) return false;',
  '    if (GetForegroundWindow() == window) return true;',
  '    if (IsIconic(window)) ShowWindowAsync(window, 9); // Restore only if minimized.',
  '    SetForegroundWindow(window);',
  '    if (GetForegroundWindow() == window) return true;',
  '    // Attach only temporarily to the current foreground input queue.',
  '    // This does not change Windows foreground-lock or security settings.',
  '    IntPtr focused = GetForegroundWindow();',
  '    uint unused;',
  '    uint thread = GetWindowThreadProcessId(focused, out unused);',
  '    uint current = GetCurrentThreadId();',
  '    if (thread != 0 && thread != current && AttachThreadInput(current, thread, true)) {',
  '      try { BringWindowToTop(window); SetForegroundWindow(window); }',
  '      finally { AttachThreadInput(current, thread, false); }',
  '    }',
  '    return GetForegroundWindow() == window;',
  '  }',
  '}',
  '"@',
  '$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json',
  'if ($payload.probe -eq $true) {',
  '  $check = New-Object -ComObject WScript.Shell',
  '  if ($null -eq $check) { exit 8 }',
  '  # Exercise native focus entrypoint on the already-focused window only.',
  '  # The probe never starts a game or transfers focus to a different app.',
  '  $foreground = [CrewFocus]::GetForegroundWindow()',
  '  if ($foreground -ne [IntPtr]::Zero) {',
  '    if (-not [CrewFocus]::Activate($foreground)) { exit 9 }',
  '  }',
  '  Write-Output "HELPER_PROBE_OK"',
  '  exit 0',
  '}',
  '$gameId = [int]$payload.pid',
  '$exe = [string]$payload.exe',
  '$account = [string]$payload.account',
  '$password = [string]$payload.password',
  'if ($gameId -le 0 -or $account -notmatch "^[A-Z][A-Z0-9_]{0,15}$" -or',
  '    [string]::IsNullOrEmpty($password) -or $password.Length -gt 16) { exit 10 }',
  '$shell = New-Object -ComObject WScript.Shell',
  'function GameWindow {',
  '  $p = Get-Process -Id $gameId -ErrorAction SilentlyContinue',
  '  if ($null -eq $p -or $p.HasExited -or $p.ProcessName -ne "WoW") { return [IntPtr]::Zero }',
  '  $resolvedPath = ""',
  '  try { $resolvedPath = [string]$p.Path } catch { }',
  '  if ($resolvedPath -and -not [string]::Equals($resolvedPath, $exe, [StringComparison]::OrdinalIgnoreCase)) { return [IntPtr]::Zero }',
  '  return [IntPtr]$p.MainWindowHandle',
  '}',
  'function GameHasFocus {',
  '  $h = GameWindow',
  '  if ($h -eq [IntPtr]::Zero -or -not [CrewFocus]::IsWindowVisible($h)) { return $false }',
  '  $active = [CrewFocus]::GetForegroundWindow()',
  '  if ($active -ne $h) { return $false }',
  '  $owner = [uint32]0',
  '  [void][CrewFocus]::GetWindowThreadProcessId($active, [ref]$owner)',
  '  return $owner -eq [uint32]$gameId',
  '}',
  'function EncodeKey([char]$letter) {',
  '  switch ([string]$letter) {',
  '    "+" { return "{+}" }',
  '    "^" { return "{^}" }',
  '    "%" { return "{%}" }',
  '    "~" { return "{~}" }',
  '    "(" { return "{(}" }',
  '    ")" { return "{)}" }',
  '    "{" { return "{{}" }',
  '    "}" { return "{}}" }',
  '    "[" { return "{[}" }',
  '    "]" { return "{]}" }',
  '    default { return [string]$letter }',
  '  }',
  '}',
  '$end = [DateTime]::UtcNow.AddSeconds(35)',
  'while ([DateTime]::UtcNow -lt $end -and (GameWindow) -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 160 }',
  'if ((GameWindow) -eq [IntPtr]::Zero) { Write-Output "NO_WOW_WINDOW"; exit 11 }',
  '# Wait for the client input queue and a short GlueXML settling interval.',
  '# Previous versions waited a fixed 4.7 seconds even on fast PCs.',
  'try { [void](Get-Process -Id $gameId).WaitForInputIdle(900) } catch { }',
  'Start-Sleep -Milliseconds 1050',
  '$focusLimit = [DateTime]::UtcNow.AddSeconds(4)',
  'while ([DateTime]::UtcNow -lt $focusLimit -and -not (GameHasFocus)) {',
  '  $window = GameWindow',
  '  if ($window -eq [IntPtr]::Zero) { Write-Output "NO_WOW_WINDOW"; exit 11 }',
  '  [void][CrewFocus]::Activate($window)',
  '  if (-not (GameHasFocus)) { [void]$shell.AppActivate($gameId) }',
  '  Start-Sleep -Milliseconds 110',
  '}',
  'if (-not (GameHasFocus)) { Write-Output "NOT_FOREGROUND"; exit 12 }',
  '# The launcher preserves the remembered account name.',
  '# Vanilla normally focuses the password box when an account is remembered.',
  '[System.Windows.Forms.SendKeys]::SendWait("^a")',
  'if (-not (GameHasFocus)) { Write-Output "FOCUS_LOST"; exit 16 }',
  '# Build the entire password + Enter sequence in memory; sending one batch',
  '# avoids a slow roundtrip to the Windows input system for each character.',
  '$sequence = New-Object System.Text.StringBuilder',
  'foreach ($letter in $password.ToCharArray()) {',
  '  [void]$sequence.Append((EncodeKey $letter))',
  '}',
  '[void]$sequence.Append("{ENTER}")',
  'if (-not (GameHasFocus)) { Write-Output "FOCUS_LOST"; exit 17 }',
  '[System.Windows.Forms.SendKeys]::SendWait($sequence.ToString())',
  'Write-Output "LOGIN_KEYS_SENT"',
].join('\n');

export function validateAutoLoginRequest({ pid, exe, account, password }) {
  if (process.platform !== 'win32' || !Number.isSafeInteger(pid) || pid < 1 ||
      typeof exe !== 'string' || !path.isAbsolute(exe) ||
      path.basename(exe).toLowerCase() !== 'wow.exe' ||
      !ACCOUNTS.includes(account) || typeof password !== 'string' ||
      password.length < 1 || password.length > 16 ||
      !/^[\x20-\x7e]+$/.test(password)) {
    throw new Error('Auto-login requires a verified WoW process and valid account.');
  }
}

export function loginHelperSource() { return SCRIPT; }

export function startAutoLogin(request, onResult = () => {}) {
  validateAutoLoginRequest(request);
  const child = spawn('powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Sta', '-Command', SCRIPT], {
      windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'],
    });
  let feedback = '';
  let complete = false;
  const finish = outcome => {
    if (complete) return;
    complete = true;
    onResult(outcome);
  };
  child.stdout.on('data', bytes => { feedback += bytes.toString('utf8').slice(0, 64); });
  child.stderr.on('data', () => {}); // stderr must not expose credentials.
  child.once('error', () => finish('helper-unavailable'));
  child.once('close', code => {
    const message = /NO_WOW_WINDOW|NOT_FOREGROUND|FOCUS_LOST|LOGIN_KEYS_SENT/.exec(feedback)?.[0];
    finish(code === 0 && message === 'LOGIN_KEYS_SENT' ?
      'keys-sent' : 'manual-login-needed-' + (message || 'code-' + String(code)).toLowerCase());
  });
  child.stdin.on('error', () => {});
  child.stdin.end(JSON.stringify({
    pid: request.pid, exe: request.exe,
    account: request.account, password: request.password,
  }));
  return child;
}
