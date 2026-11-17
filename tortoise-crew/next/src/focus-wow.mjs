import { spawn } from 'node:child_process';

// Attempts to foreground only the already-started WoW window. This helper
// does NOT type, inject, modify the game process or alter Windows policy.
const FOCUS = [
  'Add-Type -TypeDefinition @"',
  'using System;',
  'using System.Runtime.InteropServices;',
  'public static class CrewShowGame {',
  ' [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);',
  ' [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);',
  ' [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h,int action);',
  '}',
  '"@',
  '$desired = [int][Console]::In.ReadToEnd()',
  'if ($desired -le 0) { exit 2 }',
  '$deadline = [DateTime]::UtcNow.AddSeconds(6)',
  'while ([DateTime]::UtcNow -lt $deadline) {',
  ' $game = Get-Process -Id $desired -ErrorAction SilentlyContinue',
  ' if (-not $game -or $game.ProcessName -ne "WoW") { exit 3 }',
  ' $window = $game.MainWindowHandle',
  ' if ($window -ne [IntPtr]::Zero) {',
  '  if ([CrewShowGame]::IsIconic($window)) {',
  '   [void][CrewShowGame]::ShowWindowAsync($window,9)',
  '  }',
  '  if ([CrewShowGame]::SetForegroundWindow($window)) {',
  '   [Console]::Out.Write("FOCUS_REQUESTED"); exit 0',
  '  }',
  ' }',
  ' Start-Sleep -Milliseconds 120',
  '}',
  'exit 4',
].join('\n');

export function focusScript() { return FOCUS; }

export function focusVerifiedGame(pid, callback = () => {}) {
  if (process.platform !== 'win32' || !Number.isSafeInteger(pid) || pid <= 0)
    throw new Error('A verified WoW process ID is required.');
  const child = spawn('powershell.exe', [
    '-NoProfile', '-NonInteractive', '-Command', FOCUS,
  ], { windowsHide: true, stdio: ['pipe', 'ignore', 'ignore'] });
  child.once('close', code => callback(code === 0));
  child.once('error', () => callback(false));
  child.stdin.on('error', () => {});
  child.stdin.end(String(pid));
  return child;
}
