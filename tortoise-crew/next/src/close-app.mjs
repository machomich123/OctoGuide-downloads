import { spawn } from 'node:child_process';
import path from 'node:path';

const PS = [
  'Add-Type -TypeDefinition @\'',
  'using System; using System.Runtime.InteropServices; using System.Text;',
  'public static class CrewClose {',
  ' public delegate bool Callback(IntPtr h, IntPtr x);',
  ' [DllImport("user32.dll")] public static extern bool EnumWindows(Callback callback, IntPtr data);',
  ' [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);',
  ' [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder b, int max);',
  ' [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);',
  ' [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);',
  '}',
  '\'@',
  '$profile = $env:CREW_APP_PROFILE',
  '$allow = @{}',
  'Get-CimInstance Win32_Process -Filter "Name = \'msedge.exe\' OR Name = \'chrome.exe\'" |',
  ' Where-Object { $_.CommandLine -and $_.CommandLine.Contains("--app=http://127.0.0.1:") -and',
  ' $_.CommandLine.Contains("--user-data-dir=" + $profile) } |',
  ' ForEach-Object { $allow[[uint32]$_.ProcessId] = $true }',
  '$cb = [CrewClose+Callback]{ param([IntPtr]$h, [IntPtr]$x)',
  ' if (-not [CrewClose]::IsWindowVisible($h)) { return $true }',
  ' $owner = [uint32]0',
  ' [void][CrewClose]::GetWindowThreadProcessId($h, [ref]$owner)',
  ' if (-not $allow.ContainsKey($owner)) { return $true }',
  ' $title = New-Object Text.StringBuilder 300',
  ' [void][CrewClose]::GetWindowText($h, $title, $title.Capacity)',
  ' if ($title.ToString().StartsWith("Tortoise Crew Launcher", [StringComparison]::OrdinalIgnoreCase)) {',
  '  [void][CrewClose]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)',
  ' }',
  ' return $true',
  '}',
  '[void][CrewClose]::EnumWindows($cb, [IntPtr]::Zero)',
].join('\n');

export function closeAppWindow(root, onResult = () => {}) {
  if (process.platform !== 'win32' || !path.isAbsolute(root))
    throw new Error('Invalid Windows app data directory.');
  const child = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', PS], {
    env: { ...process.env, CREW_APP_PROFILE: path.join(root, 'desktop-window-profile') },
    windowsHide: true, stdio: 'ignore',
  });
  child.once('error', () => onResult(false));
  child.once('close', code => onResult(code === 0));
  child.unref();
  return child;
}
