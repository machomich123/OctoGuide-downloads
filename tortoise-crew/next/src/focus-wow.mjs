import { spawn, spawnSync } from 'node:child_process';

// Works even while WoW's window is hidden. Get-Process.MainWindowHandle
// returns zero for an invisible window, so enumerate top-level HWNDs by PID.
const FOCUS = [
  'Add-Type -TypeDefinition @"',
  'using System;',
  'using System.Runtime.InteropServices;',
  'public static class CrewGameWindow {',
  ' delegate bool Visitor(IntPtr hwnd, IntPtr arg);',
  ' [DllImport("user32.dll")] static extern bool EnumWindows(Visitor cb, IntPtr arg);',
  ' [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);',
  ' [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hwnd, uint relation);',
  ' [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);',
  ' [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();',
  ' [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);',
  ' [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);',
  ' [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr hwnd, int show);',
  ' [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);',
  ' [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);',
  ' [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr hwnd);',
  ' [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left, Top, Right, Bottom; }',
  ' public static IntPtr Find(int expected) {',
  '  IntPtr best = IntPtr.Zero;',
  '  long size = 0;',
  '  Visitor visitor = (hwnd, arg) => {',
  '   uint pid;',
  '   GetWindowThreadProcessId(hwnd, out pid);',
  '   if (pid != (uint)expected || GetWindow(hwnd, 4) != IntPtr.Zero) return true;',
  '   Rect rect;',
  '   if (!GetWindowRect(hwnd, out rect)) return true;',
  '   long area = (long)(rect.Right - rect.Left) * (rect.Bottom - rect.Top);',
  '   if (area > size && area > 20000) { size = area; best = hwnd; }',
  '   return true;',
  '  };',
  '  EnumWindows(visitor, IntPtr.Zero);',
  '  return best;',
  ' }',
  ' public static bool Visible(IntPtr hwnd) { return IsWindowVisible(hwnd); }',
  ' public static bool Foreground(IntPtr hwnd) { return GetForegroundWindow() == hwnd; }',
  ' public static string Position(IntPtr hwnd) {',
  '  Rect r; if (hwnd == IntPtr.Zero || !GetWindowRect(hwnd,out r)) return "0,0";',
  '  return r.Left.ToString() + "," + r.Top.ToString();',
  ' }',
  ' public static bool Reveal(IntPtr hwnd) {',
  '  if (hwnd == IntPtr.Zero) return false;',
  '  Rect rect;',
  '  if (GetWindowRect(hwnd, out rect) && (rect.Left < -5000 || rect.Top < -5000))',
  '    SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0, 0x15);',
  '  ShowWindowAsync(hwnd, IsIconic(hwnd) ? 9 : 5);',
  '  BringWindowToTop(hwnd);',
  '  SetForegroundWindow(hwnd);',
  '  return IsWindowVisible(hwnd);',
  ' }',
  '}',
  '"@',
  '$ErrorActionPreference="Stop"',
  '$data = [Console]::In.ReadToEnd() | ConvertFrom-Json',
  '$desired = [int]$data.pid',
  'if ($desired -le 0) { exit 2 }',
  '$game = Get-Process -Id $desired -ErrorAction SilentlyContinue',
  'if (-not $game -or $game.ProcessName -ne "WoW") { exit 3 }',
  '$window = [CrewGameWindow]::Find($desired)',
  'if ($data.mode -eq "inspect") {',
  ' [Console]::Out.Write(($window -ne [IntPtr]::Zero).ToString() + "," +',
  '  ([CrewGameWindow]::Visible($window)).ToString() + "," +',
  '  ([CrewGameWindow]::Foreground($window)).ToString() + "," +',
  '  [CrewGameWindow]::Position($window))',
  ' exit 0',
  '}',
  'if ($window -eq [IntPtr]::Zero) { exit 4 }',
  'if ([CrewGameWindow]::Reveal($window)) {',
  ' [Console]::Out.Write("WOW_REVEALED"); exit 0',
  '}',
  'exit 5',
].join('\n');

export function focusScript() { return FOCUS; }

export function focusVerifiedGame(pid, callback = () => {}) {
  if (process.platform !== 'win32' || !Number.isSafeInteger(pid) || pid <= 0)
    throw new Error('A verified WoW process ID is required.');
  const child = spawn('powershell.exe', [
    '-NoProfile', '-NonInteractive', '-Command', FOCUS,
  ], { windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'] });
  let result = '';
  child.stdout.on('data', data => { result += data.toString('utf8').slice(0, 64); });
  child.once('close', code => callback(code === 0 && result.includes('WOW_REVEALED')));
  child.once('error', () => callback(false));
  child.stdin.on('error', () => {});
  child.stdin.end(JSON.stringify({ pid, mode: 'reveal' }));
  return child;
}

// Emergency cleanup for a launcher shutdown during native startup. A parked
// game must never be stranded off-screen if its guardian is terminated.
export function revealVerifiedGameSync(pid) {
  if (process.platform !== 'win32' || !Number.isSafeInteger(pid) || pid <= 0)
    return false;
  const result = spawnSync('powershell.exe', [
    '-NoProfile', '-NonInteractive', '-Command', FOCUS,
  ], {
    windowsHide: true, encoding: 'utf8', timeout: 6000,
    input: JSON.stringify({ pid, mode: 'reveal' }),
  });
  return result.status === 0 && result.stdout.includes('WOW_REVEALED');
}

export function inspectWowWindow(pid) {
  if (process.platform !== 'win32' || !Number.isSafeInteger(pid) || pid <= 0)
    throw new Error('A valid WoW PID is required.');
  const result = spawnSync('powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command', FOCUS], {
      input: JSON.stringify({ pid, mode: 'inspect' }),
      windowsHide: true, encoding: 'utf8', timeout: 6000,
    });
  if (result.status !== 0) throw new Error('Could not inspect the WoW window.');
  const parts = result.stdout.trim().split(',');
  return {
    found: parts[0] === 'True',
    visible: parts[1] === 'True',
    foreground: parts[2] === 'True',
    left: Number(parts[3] || 0),
    top: Number(parts[4] || 0),
  };
}
