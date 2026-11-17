import { spawn } from 'node:child_process';

// WinEvent accessibility callbacks are delivered after window creation.
// A signed PowerShell helper installs this hook BEFORE VanillaFixes launches,
// hides WoW windows as soon as Windows reports a show/foreground event, then
// reveals the existing window on the actual CHARACTER_LIST_UPDATE marker.
// No key input, game injection, client binary modification or OS-policy change.
const SCRIPT = [
  'Add-Type -AssemblyName System.Windows.Forms',
  'Add-Type -TypeDefinition @"',
  'using System;',
  'using System.Diagnostics;',
  'using System.Runtime.InteropServices;',
  'public static class CrewWindowGuardian {',
  ' delegate void EventProc(IntPtr hook, uint evt, IntPtr hwnd, int idObj, int idChild, uint thread, uint time);',
  ' delegate bool WindowProc(IntPtr hwnd, IntPtr arg);',
  ' [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr module, EventProc callback, uint pid, uint thread, uint flags);',
  ' [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);',
  ' [DllImport("user32.dll")] static extern bool EnumWindows(WindowProc callback, IntPtr arg);',
  ' [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);',
  ' [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hwnd, uint relation);',
  ' [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);',
  ' [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);',
  ' [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);',
  ' [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr hwnd, int cmd);',
  ' [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);',
  ' [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr hwnd);',
  ' [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();',
  ' [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();',
  ' [DllImport("user32.dll")] static extern bool AttachThreadInput(uint attached, uint target, bool attach);',
  ' [StructLayout(LayoutKind.Sequential)] struct Rect { public int L,T,R,B; }',
  ' static EventProc callback;',
  ' static IntPtr hook;',
  ' static IntPtr creationHook;',
  ' static IntPtr foregroundHook;',
  ' public static int TotalEvents;',
  ' public static int WoWEvents;',
  ' public static int HiddenEvents;',
  ' public static int SuppressCalls;',
  ' public static int WindowMisses;',
  ' public static int LastX=99999;',
  ' public static int LastY=99999;',
  ' static int returnX=0, returnY=0;',
  ' static void Park(IntPtr hwnd) {',
  '  Rect r; if (!GetWindowRect(hwnd, out r)) return;',
  '  if (r.L == -30000 && r.T == -30000) return;',
  '  if (r.L > -4000 && r.T > -4000) { returnX=r.L; returnY=r.T; }',
  '  if (SetWindowPos(hwnd, IntPtr.Zero, -30000, -30000, 0, 0, 0x15)) HiddenEvents++;',
  ' }',
  ' static bool IsWoW(IntPtr hwnd) {',
  '  if (hwnd == IntPtr.Zero) return false;',
  '  uint pid; GetWindowThreadProcessId(hwnd, out pid);',
  '  if (pid == 0) return false;',
  '  try { return String.Equals(Process.GetProcessById((int)pid).ProcessName, "WoW", StringComparison.OrdinalIgnoreCase); }',
  '  catch { return false; }',
  ' }',
  ' public static bool Start() {',
  '  callback = (h, evt, hwnd, obj, child, thread, time) => {',
  '   TotalEvents++;',
  '   if (!IsWoW(hwnd)) return;',
  '   WoWEvents++;',
  '   if (obj != 0 || child != 0) return;',
  '   if (evt == 0x8000 || evt == 0x8002 || evt == 3) Park(hwnd);',
  '  };',
  '  creationHook = SetWinEventHook(0x8000, 0x8000, IntPtr.Zero, callback, 0, 0, 0);',
  '  hook = SetWinEventHook(0x8002, 0x8002, IntPtr.Zero, callback, 0, 0, 0);',
  '  foregroundHook = SetWinEventHook(3, 3, IntPtr.Zero, callback, 0, 0, 0);',
  '  return creationHook != IntPtr.Zero && hook != IntPtr.Zero && foregroundHook != IntPtr.Zero;',
  ' }',
  ' public static void Stop() {',
  '  if (creationHook != IntPtr.Zero) { UnhookWinEvent(creationHook); creationHook = IntPtr.Zero; }',
  '  if (hook != IntPtr.Zero) { UnhookWinEvent(hook); hook = IntPtr.Zero; }',
  '  if (foregroundHook != IntPtr.Zero) { UnhookWinEvent(foregroundHook); foregroundHook = IntPtr.Zero; }',
  ' }',
  ' public static IntPtr Find(int expected) {',
  '  IntPtr result = IntPtr.Zero; long best = 0;',
  '  WindowProc visit = (hwnd,arg) => {',
  '   uint pid; GetWindowThreadProcessId(hwnd,out pid);',
  '   if ((int)pid != expected || GetWindow(hwnd,4) != IntPtr.Zero) return true;',
  '   Rect r; if (!GetWindowRect(hwnd,out r)) return true;',
  '   long area=(long)(r.R-r.L)*(r.B-r.T);',
  '   if (area > best && area > 20000) {best=area;result=hwnd;}',
  '   return true;',
  '  };',
  '  EnumWindows(visit,IntPtr.Zero); return result;',
  ' }',
  ' public static bool Visible(int expected) {',
  '  IntPtr hwnd=Find(expected);return hwnd!=IntPtr.Zero && IsWindowVisible(hwnd);',
  ' }',
  ' public static bool Suppress(int expected) {',
  '  SuppressCalls++;',
  '  IntPtr hwnd=Find(expected);',
  '  if (hwnd==IntPtr.Zero) {WindowMisses++;return false;}',
  '  Rect r; if (GetWindowRect(hwnd,out r)) {LastX=r.L;LastY=r.T;}',
  '  Park(hwnd);',
  '  return true;',
  ' }',
  ' public static bool Reveal(int expected) {',
  '  IntPtr hwnd=Find(expected); if(hwnd==IntPtr.Zero)return false;',
  '  SetWindowPos(hwnd, IntPtr.Zero, returnX, returnY, 0, 0, 0x15);',
  '  ShowWindowAsync(hwnd,5); BringWindowToTop(hwnd); SetForegroundWindow(hwnd);',
  '  if (GetForegroundWindow()!=hwnd) {',
  '   IntPtr old=GetForegroundWindow(); uint unused;',
  '   uint thread=GetWindowThreadProcessId(old,out unused);',
  '   uint current=GetCurrentThreadId();',
  '   if (thread!=0 && thread!=current && AttachThreadInput(current,thread,true)) {',
  '    try { BringWindowToTop(hwnd); SetForegroundWindow(hwnd); }',
  '    finally { AttachThreadInput(current,thread,false); }',
  '   }',
  '  }',
  '  return IsWindowVisible(hwnd);',
  ' }',
  '}',
  '"@',
  '$ErrorActionPreference="Stop"',
  '$request = [Console]::In.ReadToEnd() | ConvertFrom-Json',
  '$marker = [string]$request.marker',
  '$limit = [int]$request.timeoutMs',
  'if (-not [IO.Path]::IsPathRooted($marker) -or $limit -lt 4000 -or $limit -gt 60000) { exit 2 }',
  'if (-not [CrewWindowGuardian]::Start()) { exit 3 }',
  '[Console]::Out.WriteLine("GUARD_READY")',
  '[Console]::Out.Flush()',
  '$begin = [DateTime]::UtcNow',
  '$seen = $false',
  '$pidGame = 0',
  '$outcome = "FALLBACK_VISIBLE"',
  'try {',
  ' while (([DateTime]::UtcNow - $begin).TotalMilliseconds -lt $limit) {',
  '  [System.Windows.Forms.Application]::DoEvents()',
  '  $process = Get-Process -Name WoW -ErrorAction SilentlyContinue | Select-Object -First 1',
  '  if ($process) {',
  '   $seen=$true; $pidGame=$process.Id',
  '   [void][CrewWindowGuardian]::Suppress($pidGame)',
  '  }',
  '  elseif ($seen) { $outcome="GAME_EXITED";break }',
  '  if ($seen -and [IO.File]::Exists($marker)) {',
  '   $data = [IO.File]::ReadAllText($marker)',
  '   if ($data.Contains("CREW_CHARACTER_LIST_READY")) {',
  '    $outcome="CHARACTER_VISIBLE";break',
  '   }',
  '  }',
  '  Start-Sleep -Milliseconds 18',
  ' }',
  '} finally { [CrewWindowGuardian]::Stop() }',
  'if ($seen -and $outcome -ne "GAME_EXITED") {',
  ' $shown = [CrewWindowGuardian]::Reveal($pidGame)',
  ' [Console]::Out.WriteLine($outcome + "," + $shown + "," +',
  '  [Math]::Round(([DateTime]::UtcNow - $begin).TotalMilliseconds) + "," +',
  '  [CrewWindowGuardian]::HiddenEvents + "," +',
  '  [CrewWindowGuardian]::WoWEvents + "," +',
  '  [CrewWindowGuardian]::TotalEvents + "," +',
  '  [CrewWindowGuardian]::SuppressCalls + "," +',
  '  [CrewWindowGuardian]::WindowMisses + "," +',
  '  [CrewWindowGuardian]::LastX + "," +',
  '  [CrewWindowGuardian]::LastY)',
  '} else { [Console]::Out.WriteLine($outcome + ",False," +',
  '  [CrewWindowGuardian]::HiddenEvents + "," +',
  '  [CrewWindowGuardian]::WoWEvents + "," +',
  '  [CrewWindowGuardian]::TotalEvents + "," +',
  '  [CrewWindowGuardian]::SuppressCalls + "," +',
  '  [CrewWindowGuardian]::WindowMisses + "," +',
  '  [CrewWindowGuardian]::LastX + "," +',
  '  [CrewWindowGuardian]::LastY) }',
  '[Console]::Out.Flush()',
].join('\n');

export function guardianScript() { return SCRIPT; }

export function startWindowGuardian(marker, { timeoutMs = 25000 } = {}) {
  if (process.platform !== 'win32')
    throw new Error('The native window guardian needs Windows.');
  const child = spawn('powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Sta', '-Command', SCRIPT], {
      windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'],
    });
  let buffer = '';
  let ready = false;
  let ended = false;
  let settleReady, rejectReady, settleResult;
  const armed = new Promise((resolve, reject) => {
    settleReady = resolve; rejectReady = reject;
  });
  const finished = new Promise(resolve => { settleResult = resolve; });
  const startup = setTimeout(() => {
    if (!ready) {
      child.kill();
      rejectReady(new Error('Windows window-guard initialization timed out.'));
    }
  }, 11000);
  child.stdout.on('data', chunk => {
    buffer += chunk.toString('utf8');
    while (buffer.includes('\n')) {
      const index = buffer.indexOf('\n');
      const line = buffer.slice(0, index).trim();
      buffer = buffer.slice(index + 1);
      if (line === 'GUARD_READY' && !ready) {
        ready = true;
        clearTimeout(startup);
        settleReady();
      } else if (line.startsWith('CHARACTER_VISIBLE,') ||
          line.startsWith('FALLBACK_VISIBLE,') ||
          line.startsWith('GAME_EXITED,')) {
        settleResult(line);
        ended = true;
      }
    }
  });
  child.once('error', error => {
    clearTimeout(startup);
    if (!ready) rejectReady(error);
    if (!ended) settleResult('GUARD_ERROR');
  });
  child.once('close', () => {
    clearTimeout(startup);
    if (!ready) rejectReady(new Error('Window guardian could not start.'));
    if (!ended) settleResult('GUARD_EXIT');
  });
  child.stderr.on('data', () => {}); // No console windows or secret logs.
  child.stdin.on('error', () => {});
  child.stdin.end(JSON.stringify({ marker, timeoutMs }));
  return { child, armed, finished };
}
